#!/usr/bin/env python3
"""telemetry-hub — one place that shows what every machine's LLDP telemetry says, for NerveCentre (or anyone) to hook into.

Machines push the same record they announce over LLDP (tools/lldp/sysmedic-lldp-telemetry) to POST /ingest every 30 s.
  POST /ingest        a JSON record {"h": host, "up": s, "l": load, "m": mem%, "d": disk%, "t": °C, "sv": [...], ...}
  GET  /api/fleet     {"updated": ts, "hosts": [{... record ..., "ip", "age_s", "state": up|stale|down, "flags": [...]}]}
  GET  /api/host/NAME one host
  GET  /fleet         a self-refreshing page of cards (works inside an iframe or under a path prefix)
  GET  /health        ok
LAN-first trust, like NerveCentre: only private source addresses may push; records are size-limited and schema-checked,
and nothing in them is ever executed or written outside the state file. Standard library only.

  telemetry-hub.py [--host 0.0.0.0] [--port 8471] [--state /var/lib/sysmedic-telemetry/state.json]
"""
import ipaddress
import json
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY = 8192
STALE, DOWN = 90, 300
NAME = re.compile(r"^[A-Za-z0-9._-]{1,48}$")
NUM = ("up", "l", "m", "d", "t", "cpu", "ct", "ts")
STATE = {"path": None, "hosts": {}}
LOCK = threading.Lock()
LAST = {}


def clean(rec):
    """Only known fields, with the right types; anything else is dropped."""
    if not isinstance(rec, dict) or not NAME.match(str(rec.get("h", ""))):
        return None
    out = {"h": rec["h"]}
    for k in NUM:
        v = rec.get(k)
        if isinstance(v, (int, float)) and not isinstance(v, bool) and -1e9 < v < 1e12:
            out[k] = v
    for k, n in (("os", 80), ("k", 60), ("sm", 40)):
        if isinstance(rec.get(k), str):
            out[k] = re.sub(r"[^\x20-\x7e]", "", rec[k])[:n]
    if isinstance(rec.get("sv"), list):
        out["sv"] = [re.sub(r"[^\x20-\x7e]", "", str(x))[:40] for x in rec["sv"][:12]]
    return out


def private(ip):
    try:
        a = ipaddress.ip_address(ip.split("%")[0].replace("::ffff:", ""))
        return a.is_private or a.is_loopback or a.is_link_local
    except ValueError:
        return False


def flags(r):
    f = []
    if r.get("d", 0) >= 90:
        f.append(f"disk {r['d']}% full")
    if r.get("m", 0) >= 90:
        f.append(f"memory {r['m']}% used")
    if r.get("t", 0) >= 85:
        f.append(f"{r['t']} °C")
    if r.get("cpu") and r.get("l", 0) > 2 * r["cpu"]:
        f.append(f"load {r['l']} on {r['cpu']} cores")
    return f


def fleet():
    now = time.time()
    hosts = []
    with LOCK:
        for name, h in sorted(STATE["hosts"].items()):
            age = now - h["received"]
            hosts.append(dict(h["rec"], ip=h["ip"], age_s=int(age), state="up" if age < STALE else "stale" if age < DOWN else "down",
                              flags=flags(h["rec"]) if age < DOWN else []))
    return {"updated": int(now), "hosts": hosts}


def save():
    p = STATE["path"]
    if not p:
        return
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with LOCK:
            data = json.dumps(STATE["hosts"])
        with open(p + ".tmp", "w") as f:
            f.write(data)
        os.replace(p + ".tmp", p)
    except OSError:
        pass


PAGE = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Fleet telemetry</title><style>
:root{--bg:#0b1118;--card:#121c27;--ink:#dbe7f3;--dim:#7d93a8;--ok:#3ad29f;--warn:#f2b84b;--bad:#ef6a6a;--acc:#4cc9f0}
@media (prefers-color-scheme:light){:root{--bg:#f3f6f9;--card:#fff;--ink:#14212d;--dim:#5b7083;--ok:#168a63;--warn:#b57a0c;--bad:#c23b3b;--acc:#0a7ea4}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.4 system-ui,sans-serif;padding:16px}
h1{font-size:18px;margin:0 0 4px}small{color:var(--dim)}
.grid{display:grid;gap:12px;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));margin-top:14px}
.card{background:var(--card);border-radius:10px;padding:14px;border-left:4px solid var(--ok)}
.card.stale{border-color:var(--warn)}.card.down{border-color:var(--bad);opacity:.7}.card.flag{border-color:var(--warn)}
.name{font-weight:700;font-size:17px}.os{color:var(--dim);font-size:13px}
.row{display:flex;align-items:center;gap:8px;margin-top:8px;font-size:13px}.row b{width:48px;color:var(--dim);font-weight:500}
.bar{flex:1;height:8px;background:rgba(127,127,127,.2);border-radius:4px;overflow:hidden}.bar i{display:block;height:100%;background:var(--acc)}
.bar i.hi{background:var(--warn)}.bar i.crit{background:var(--bad)}
.chips{margin-top:10px;display:flex;flex-wrap:wrap;gap:4px}.chips span{background:rgba(127,127,127,.18);border-radius:10px;padding:1px 8px;font-size:12px}
.flags{margin-top:8px;color:var(--warn);font-size:13px}
</style></head><body><h1>Fleet telemetry</h1><small id=s>loading…</small><div class=grid id=g></div><script>
const E=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function bar(v,max){if(v==null)return'';const p=Math.min(100,Math.round(100*v/max));return`<div class=bar><i class="${p>=90?'crit':p>=75?'hi':''}" style="width:${p}%"></i></div>`}
function dur(s){const d=Math.floor(s/86400),h=Math.floor(s%86400/3600);return d?`${d}d ${h}h`:`${h}h ${Math.floor(s%3600/60)}m`}
async function load(){try{const r=await (await fetch('api/fleet',{cache:'no-store'})).json();
document.getElementById('s').textContent=r.hosts.length+' machines · updated '+new Date(r.updated*1000).toLocaleTimeString();
document.getElementById('g').innerHTML=r.hosts.map(h=>`<div class="card ${h.state} ${h.flags.length?'flag':''}"><div class=name>${E(h.h)} <small>${E(h.ip)} · ${h.state==='up'?'up':h.state+' '+dur(h.age_s)}</small></div>
<div class=os>${E(h.os||'')}${h.sm?' · SM '+E(h.sm):''}${h.up!=null?' · up '+dur(h.up):''}</div>
<div class=row><b>load</b>${bar(h.l,h.cpu||4)}<span>${h.l??'?'}${h.cpu?' / '+h.cpu:''}</span></div>
<div class=row><b>memory</b>${bar(h.m,100)}<span>${h.m??'?'}%</span></div>
<div class=row><b>disk</b>${bar(h.d,100)}<span>${h.d??'?'}%</span></div>
${h.t?`<div class=row><b>temp</b>${bar(h.t,100)}<span>${h.t} °C</span></div>`:''}
${h.ct!=null?`<div class=row><b>docker</b><span>${h.ct} containers</span></div>`:''}
${(h.sv&&h.sv.length)?`<div class=chips>${h.sv.map(x=>`<span>${E(x)}</span>`).join('')}</div>`:''}
${h.flags.length?`<div class=flags>⚠ ${h.flags.map(E).join(' · ')}</div>`:''}</div>`).join('')}catch(e){document.getElementById('s').textContent='hub unreachable'}}
load();setInterval(load,15000)</script></body></html>"""


class H(BaseHTTPRequestHandler):
    server_version = "telemetry-hub"

    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        b = body if isinstance(body, bytes) else (body if isinstance(body, str) else json.dumps(body)).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + ("; charset=utf-8" if "text" in ctype or "json" in ctype else ""))
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if ctype == "application/json":
            self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        p = self.path.split("?")[0].rstrip("/") or "/"
        if p == "/health":
            return self.send(200, "ok", "text/plain")
        if p == "/api/fleet":
            return self.send(200, fleet())
        if p.startswith("/api/host/"):
            n = p[len("/api/host/"):]
            h = next((x for x in fleet()["hosts"] if x["h"] == n), None)
            return self.send(200, h) if h else self.send(404, {"error": "unknown host"})
        if p in ("/", "/fleet"):
            return self.send(200, PAGE, "text/html")
        self.send(404, {"error": "not found"})

    def do_POST(self):
        ip = self.client_address[0]
        if self.path.split("?")[0] != "/ingest":
            return self.send(404, {"error": "not found"})
        if not private(ip):
            return self.send(403, {"error": "private addresses only"})
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > MAX_BODY:
            return self.send(413, {"error": "body must be 1..%d bytes" % MAX_BODY})
        try:
            rec = clean(json.loads(self.rfile.read(n)))
        except ValueError:
            rec = None
        if not rec:
            return self.send(400, {"error": "not a telemetry record"})
        now = time.time()
        if now - LAST.get(ip, 0) < 2:
            return self.send(429, {"error": "slow down"})
        LAST[ip] = now
        with LOCK:
            if len(STATE["hosts"]) >= 200 and rec["h"] not in STATE["hosts"]:
                return self.send(507, {"error": "too many hosts"})
            STATE["hosts"][rec["h"]] = {"rec": rec, "ip": ip.replace("::ffff:", ""), "received": now}
        save()
        self.send(200, {"ok": True})


def main(a):
    host = a[a.index("--host") + 1] if "--host" in a else "0.0.0.0"
    port = int(a[a.index("--port") + 1]) if "--port" in a else 8471
    STATE["path"] = a[a.index("--state") + 1] if "--state" in a else None
    if STATE["path"] and os.path.exists(STATE["path"]):
        try:
            with open(STATE["path"]) as f:
                STATE["hosts"] = json.load(f)
        except (OSError, ValueError):
            pass
    ThreadingHTTPServer((host, port), H).serve_forever()


if __name__ == "__main__":
    main(sys.argv[1:])
