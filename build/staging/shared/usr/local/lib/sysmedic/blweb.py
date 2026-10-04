"""blweb — BitLocker unlock from a phone or laptop on the same network (sysmedic-win bitlocker-web).

For when the recovery key is with someone else (the customer, their IT admin) or on the engineer's
phone. The engineer starts it on the rescue computer's console; it is never started automatically.

Safety:
  - HTTPS with a certificate made for this run (the key never crosses the network in clear text);
    the browser warns because it's self-signed, and the console shows its fingerprint to compare
  - a random secret in the URL (shown as a QR code on the console); anything else gets 404
  - read-only unlock only; 5 wrong keys, 30 bad requests or 15 minutes and it stops by itself
  - the key goes straight to cryptsetup on stdin: never stored, logged, printed or kept in memory
    longer than the request; requests are not logged
"""
import html
import http.server
import json
import os
import secrets
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import time

MAX_FAILURES, MAX_BAD_REQUESTS, LIFETIME = 5, 30, 15 * 60


def lan_addresses():
    out = subprocess.run(["ip", "-j", "-4", "addr"], capture_output=True, text=True).stdout
    try:
        return [a["local"] for i in json.loads(out) if i["ifname"] != "lo" for a in i.get("addr_info", [])]
    except (json.JSONDecodeError, KeyError):
        return []


def make_cert(d, ips):
    san = ",".join(f"IP:{ip}" for ip in ips)
    subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes",
                    "-days", "1", "-subj", "/CN=SysMedic BitLocker unlock", "-addext", f"subjectAltName={san}",
                    "-keyout", f"{d}/key.pem", "-out", f"{d}/cert.pem"], check=True, capture_output=True)
    fp = subprocess.run(["openssl", "x509", "-in", f"{d}/cert.pem", "-noout", "-fingerprint", "-sha256"],
                        capture_output=True, text=True).stdout.strip().split("=", 1)[-1]
    return fp


PAGE = """<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><meta name=referrer content=no-referrer>
<title>SysMedic · BitLocker unlock</title><style>
:root{--bg:#f6f7f9;--card:#fff;--text:#16181d;--muted:#5d6470;--line:#d9dde3;--brand:#c62828;--ok:#1b7f3a;--bad:#b3261e}
@media (prefers-color-scheme:dark){:root{--bg:#111316;--card:#1b1e23;--text:#e9ebef;--muted:#a0a7b2;--line:#2c3138;--brand:#ef5350;--ok:#5cc27a;--bad:#ff8a80}}
*{box-sizing:border-box}body{margin:0;font:16px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--text)}
header{padding:18px 16px 6px}h1{margin:0;font-size:20px}h1 b{color:var(--brand)}.sub{color:var(--muted);font-size:14px}
main{max-width:560px;margin:0 auto;padding:8px 16px 32px}.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:12px 0}
label{display:block;font-weight:600;margin:12px 0 6px}.vol{display:flex;gap:10px;align-items:flex-start;padding:10px;border:1px solid var(--line);border-radius:10px;margin:6px 0}
.vol small{color:var(--muted);display:block}input[type=text]{width:100%;font:18px/1.3 ui-monospace,Menlo,Consolas,monospace;padding:12px;border:1px solid var(--line);border-radius:10px;background:var(--bg);color:var(--text);letter-spacing:.5px}
button{margin-top:14px;width:100%;padding:14px;border:0;border-radius:10px;background:var(--brand);color:#fff;font-size:17px;font-weight:600}
button:disabled{opacity:.55}.msg{margin-top:12px;font-weight:600}.ok{color:var(--ok)}.bad{color:var(--bad)}.muted{color:var(--muted);font-size:14px}
</style></head><body><header><h1><b>Sys</b>Medic · BitLocker unlock</h1><div class=sub>__MACHINE__</div></header><main>
<div class=card><p style=margin-top:0>Enter the <b>48-digit recovery key</b> for this computer's encrypted drive. It unlocks the drive <b>read-only</b> for the engineer, and is never stored or logged.</p>
<p class=muted>Where to find it: <b>aka.ms/myrecoverykey</b> (the Microsoft account that set the PC up), your IT department (Entra ID / Active Directory), or a printout. Match the <b>Key ID</b> shown below.</p></div>
<form class=card id=f autocomplete=off><label>Encrypted drive</label><div id=vols>__VOLUMES__</div>
<label for=k>Recovery key</label><input type=text id=k inputmode=numeric autocomplete=off autocapitalize=off spellcheck=false placeholder="123456-123456-123456-123456-123456-123456-123456-123456">
<div class=muted id=count>0 of 48 digits</div><button id=b>Unlock</button><div class=msg id=m role=status></div></form>
<p class=muted>Secure link for this visit only; it stops by itself after unlocking or 15 minutes.</p></main>
<script>
const T=__TOKEN__,k=document.getElementById('k'),m=document.getElementById('m'),b=document.getElementById('b');
k.addEventListener('input',()=>{const d=k.value.replace(/\\D/g,'').slice(0,48);if(/^[\\d\\s-]*$/.test(k.value))k.value=d.replace(/(\\d{6})(?=\\d)/g,'$1-');
document.getElementById('count').textContent=d.length+' of 48 digits'});
document.getElementById('f').addEventListener('submit',async e=>{e.preventDefault();const v=document.querySelector('input[name=dev]:checked');
if(!v){m.className='msg bad';m.textContent='Choose the drive first.';return}
b.disabled=true;m.className='msg';m.textContent='Unlocking… (up to a minute)';
try{const r=await fetch(T+'/unlock',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({dev:v.value,key:k.value})});
const j=await r.json();m.className='msg '+(j.ok?'ok':'bad');m.textContent=j.message;if(j.ok){k.value='';k.disabled=true}else{b.disabled=false}}
catch(err){m.className='msg bad';m.textContent='Connection lost: the unlock link may have closed. Ask the engineer.';b.disabled=false}});
</script></body></html>"""


def key_id(dev):
    """BitLocker Key ID (identifier of the recovery password), so the owner picks the right key."""
    out = subprocess.run(["cryptsetup", "bitlkDump", dev], capture_output=True, text=True).stdout
    cur = None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("GUID:"):
            cur = s.split(":", 1)[1].strip()
        if "recovery passphrase" in s.lower() and cur:
            return cur.upper()
    return ""


def serve(volumes, unlock, mount, audit, machine="", color=None):
    """volumes(): [(dev, size, label)]; unlock(dev, key) -> (ok, msg, mapped); mount(name) -> (mp, err)."""
    C = color or {k: "" for k in ("red", "yel", "grn", "cyan", "bold", "dim", "end")}
    ips = lan_addresses()
    if not ips:
        print(f"  {C['yel']}No network.{C['end']} Connect first (wifi, or Ethernet), then run this again.")
        return 1
    if not shutil.which("openssl"):
        print("  openssl is missing; use the console unlock: sysmedic-win bitlocker DEV")
        return 1
    vols = volumes()
    if not vols:
        print("  No BitLocker volumes on this machine.")
        return 1
    tmp = tempfile.mkdtemp(prefix="sysmedic-blweb-", dir="/run")
    os.chmod(tmp, 0o700)
    fingerprint = make_cert(tmp, ips)
    token = "/" + secrets.token_urlsafe(18)
    state = {"failures": 0, "bad": 0, "done": set(), "stop": "", "started": time.time()}
    lock = threading.Lock()
    ids = {dev: key_id(dev) for dev, _, _ in vols}

    def volume_html():
        rows = []
        for i, (dev, size, label) in enumerate(vols):
            unlocked = os.path.exists(f"/dev/mapper/bitlocker-{os.path.basename(dev)}")
            kid = f"<small>Key ID: <b>{html.escape(ids[dev][:8])}</b>…</small>" if ids.get(dev) else ""
            rows.append(f"<label class=vol><input type=radio name=dev value='{html.escape(dev)}' {'checked' if i == 0 and not unlocked else ''}"
                        f"{' disabled' if unlocked else ''}><span>{html.escape(dev)} · {html.escape(size)}"
                        f"{(' · ' + html.escape(label)) if label else ''}{' — <b>already unlocked</b>' if unlocked else ''}{kid}</span></label>")
        return "".join(rows)

    class Handler(http.server.BaseHTTPRequestHandler):
        server_version, sys_version = "SysMedic", ""

        def log_message(self, *a):          # nothing is logged: the URL holds the secret
            pass

        def send(self, code, body, ctype="text/html; charset=utf-8"):
            data = body.encode() if isinstance(body, str) else body
            self.send_response(code)
            for h, v in (("Content-Type", ctype), ("Content-Length", str(len(data))), ("Cache-Control", "no-store"),
                         ("Referrer-Policy", "no-referrer"), ("X-Frame-Options", "DENY"), ("X-Content-Type-Options", "nosniff"),
                         ("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'")):
                self.send_header(h, v)
            self.end_headers()
            self.wfile.write(data)

        def bad(self):
            with lock:
                state["bad"] += 1
                if state["bad"] >= MAX_BAD_REQUESTS:
                    state["stop"] = "too many wrong links (someone probing the network?)"
            self.send(404, "Not found", "text/plain")

        def do_GET(self):
            if self.path.split("?")[0] != token:
                return self.bad()
            page = PAGE.replace("__TOKEN__", json.dumps(token)).replace("__VOLUMES__", volume_html()) \
                       .replace("__MACHINE__", html.escape(machine or "this computer"))
            self.send(200, page)

        def do_POST(self):
            if self.path != token + "/unlock":
                return self.bad()
            try:
                n = int(self.headers.get("Content-Length", "0"))
                req = json.loads(self.rfile.read(min(n, 4096)) or b"{}")
            except (ValueError, json.JSONDecodeError):
                return self.send(400, json.dumps({"ok": False, "message": "Bad request"}), "application/json")
            dev, key = str(req.get("dev", "")), str(req.get("key", "")).strip()
            req = None
            if dev not in {v[0] for v in vols}:
                return self.send(400, json.dumps({"ok": False, "message": "Unknown drive"}), "application/json")
            if not key:
                return self.send(400, json.dumps({"ok": False, "message": "Enter the key"}), "application/json")
            with lock:
                if state["stop"]:
                    return self.send(410, json.dumps({"ok": False, "message": "This unlock link has closed."}), "application/json")
                ok, msg, mapped = unlock(dev, key)
                key = None
                if ok:
                    state["done"].add(dev)
                    mp, err = mount(os.path.basename(mapped)) if mapped else (None, "")
                    print(f"\n  {C['grn']}Unlocked: {dev} from {self.client_address[0]}{C['end']} → {mapped}" +
                          (f"; files at {mp}" if mp else (f" ({C['yel']}NTFS won't mount: {err}{C['end']})" if err else "")))
                    if all(os.path.exists(f"/dev/mapper/bitlocker-{os.path.basename(v[0])}") for v in vols):
                        state["stop"] = "all BitLocker volumes unlocked"
                    msg = "Unlocked (read-only). The engineer can carry on now — you can close this page."
                else:
                    state["failures"] += 1
                    left = MAX_FAILURES - state["failures"]
                    print(f"\n  {C['yel']}Wrong key for {dev} from {self.client_address[0]} ({left} attempt(s) left){C['end']}")
                    time.sleep(2)
                    if left <= 0:
                        state["stop"] = f"{MAX_FAILURES} wrong keys"
                    msg = (f"That key didn't work for {dev}. Check it matches the Key ID shown. {left} attempt(s) left."
                           if left > 0 else "Too many wrong keys: the link has closed. Ask the engineer.")
            self.send(200, json.dumps({"ok": ok, "message": msg}), "application/json")

    httpd = None
    for port in range(8443, 8453):
        try:
            httpd = http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler)
            break
        except OSError:
            continue
    if not httpd:
        print("  No free port (8443-8452).")
        return 1
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(f"{tmp}/cert.pem", f"{tmp}/key.pem")
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    httpd.timeout = 1
    shutil.rmtree(tmp, ignore_errors=True)        # loaded into memory; nothing left on disk

    url = f"https://{ips[0]}:{port}{token}"
    print(f"\n  {C['bold']}BitLocker unlock from a phone or laptop on the same network{C['end']}")
    print(f"  Scan the QR code, or type the address. {C['dim']}(The browser warns about the certificate: it's made for this")
    print(f"  visit only. Check its SHA-256 fingerprint starts {fingerprint[:23]}, then continue.){C['end']}\n")
    qr = subprocess.run(["qrencode", "-t", "UTF8", "-m", "1", url], capture_output=True, text=True).stdout \
        if shutil.which("qrencode") else ""
    print("\n".join("    " + l for l in qr.splitlines()) if qr else "")
    print(f"\n  {C['cyan']}{url}{C['end']}")
    for ip in ips[1:]:
        print(f"  {C['dim']}also: https://{ip}:{port}{token}{C['end']}")
    for dev, size, label in vols:
        print(f"  {dev} ({size}{', ' + label if label else ''})" + (f"  Key ID {ids[dev][:8]}…" if ids.get(dev) else ""))
    print(f"\n  {C['dim']}Waiting. It stops after unlocking, 5 wrong keys or 15 minutes; Ctrl-C to stop now.{C['end']}")
    audit(f"BitLocker web unlock started on port {port} (HTTPS, secret link, read-only)")

    def stopper():
        while not state["stop"]:
            if time.time() - state["started"] > LIFETIME:
                state["stop"] = "15 minutes passed"
            time.sleep(1)
        time.sleep(1.5)                    # let the last page load its result
        httpd.shutdown()

    threading.Thread(target=stopper, daemon=True).start()
    try:
        httpd.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        state["stop"] = "stopped by the engineer"
    finally:
        httpd.server_close()
    audit(f"BitLocker web unlock stopped: {state['stop']} ({len(state['done'])} unlocked)")
    print(f"\n  Web unlock stopped: {state['stop']}.")
    return 0 if state["done"] else 1
