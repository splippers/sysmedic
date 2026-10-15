#!/usr/bin/env python3
"""SysMedic mailbox server — "the hospital". Runs on the build PC; rescue computers ("ambulances") post redacted
questions and findings to it over HTTPS and read the replies. It is a mailbox, never remote control: nothing here
can run anything on a rescue computer.

  POST /api/post                  {"text": "...", "kind": "question|finding|status"}   (Authorization: Bearer TOKEN)
  GET  /api/replies?since=N       replies addressed to the calling machine
  POST /mcp                       the same two tools over MCP (streamable HTTP, JSON-RPC): post_message, read_replies
  GET  /client                    the rescue-side program (public; no secrets), for machines that haven't been redeployed yet
  GET  /health

Every machine has its own token (stored only as a hash). Text that looks unredacted (email, MAC, public IP, a user
folder, a recovery key, a private key) is refused with the reason, so a bug on the machine can't leak it.
Data lives in $MAILBOX_DIR (default ~/sysmedic-mailbox, mode 700): customer-derived, never committed.
"""
import hashlib
import json
import os
import re
import ssl
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

DIR = Path(os.environ.get("MAILBOX_DIR", os.path.expanduser("~/sysmedic-mailbox")))
MAX_TEXT = 12000
LOCK = threading.Lock()
LAST = {}                                           # machine -> recent post times (rate limit)

REFUSE = [
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"), "an email address"),
    (re.compile(r"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"), "a MAC address"),
    (re.compile(r"\b(?:\d{6}-){7}\d{6}\b"), "a BitLocker recovery key"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "a private key"),
    (re.compile(r"(?i)[a-z]:\\users\\(?!USER_\d|Public\b|Default\b|All Users\b|\*|<)[^\\\s]+"), "a user folder name"),
    (re.compile(r"(?i)/home/(?!USER_\d|<)[a-z][\w.-]*/"), "a home folder name"),
]
IPV4 = re.compile(r"\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b")


def public_ip(text):
    for m in IPV4.finditer(text):
        a, b, c, d = map(int, m.groups())
        if max(a, b, c, d) > 255:
            continue
        if a in (10, 127, 0) or (a == 192 and b == 168) or (a == 172 and 16 <= b <= 31) or (a == 169 and b == 254):
            continue
        if re.search(r"(?i)(version|ver\.?|v|build|kernel|driver|bios|firmware|fw)\s*[:=]?\s*$", text[max(0, m.start() - 14):m.start()]):
            continue                                 # looks like a version number
        return m.group(0)
    return None


def why_refused(text):
    for rx, what in REFUSE:
        if rx.search(text):
            return what
    ip = public_ip(text)
    return f"a public IP address ({ip})" if ip else None


CLIENT = Path(__file__).resolve().parent.parent.parent / "build/staging/shared/usr/local/bin/sysmedic-hospital"


def client_sha():
    return hashlib.sha256(CLIENT.read_bytes()).hexdigest()


def h(token):
    return hashlib.sha256(token.encode()).hexdigest()


def machines():
    try:
        return json.loads((DIR / "machines.json").read_text())
    except (OSError, ValueError):
        return {}


def who(token):
    return next((n for n, m in machines().items() if m.get("hash") == h(token) and not m.get("revoked")), None)


def append(msg):
    with LOCK:
        f = DIR / "messages.jsonl"
        n = sum(1 for _ in open(f)) if f.exists() else 0
        msg = dict(msg, id=n + 1, ts=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
        with open(f, "a") as fh:
            fh.write(json.dumps(msg) + "\n")
        os.chmod(f, 0o600)
    return msg


def messages():
    try:
        return [json.loads(l) for l in open(DIR / "messages.jsonl") if l.strip()]
    except OSError:
        return []


def do_post(name, text, kind="question"):
    text = (text or "").strip()
    if not text:
        return 400, {"error": "empty message"}
    if len(text) > MAX_TEXT:
        return 413, {"error": f"too long ({len(text)} > {MAX_TEXT} characters): send a summary"}
    bad = why_refused(text)
    if bad:
        return 422, {"error": f"refused: the message contains {bad}. Redact it first (sysmedic-hospital does this; "
                              "if it still got through, the redactor missed something: note it with sysmedic-note --feedback)."}
    now = time.time()
    recent = [t for t in LAST.get(name, []) if now - t < 60]
    if len(recent) >= 20:
        return 429, {"error": "too many messages; wait a minute"}
    LAST[name] = recent + [now]
    m = append({"dir": "in", "machine": name, "kind": kind if kind in ("question", "finding", "status") else "question", "text": text})
    return 200, {"ok": True, "id": m["id"]}


def do_replies(name, since):
    return 200, {"replies": [{"id": m["id"], "ts": m["ts"], "text": m["text"]}
                             for m in messages() if m["dir"] == "out" and m["machine"] == name and m["id"] > since]}


TOOLS = [
    {"name": "post_message", "description": "Send a redacted question, finding or status to the hospital (the engineer's Claude).",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}, "kind": {"type": "string", "enum": ["question", "finding", "status"]}}, "required": ["text"]}},
    {"name": "read_replies", "description": "Read the hospital's replies to this machine.",
     "inputSchema": {"type": "object", "properties": {"since_id": {"type": "integer"}}}},
]


def mcp(name, req):
    method, rid = req.get("method"), req.get("id")
    ok = lambda r: {"jsonrpc": "2.0", "id": rid, "result": r}  # noqa: E731
    if method == "initialize":
        return ok({"protocolVersion": "2025-03-26", "capabilities": {"tools": {}}, "serverInfo": {"name": "sysmedic-hospital", "version": "1"}})
    if method == "tools/list":
        return ok({"tools": TOOLS})
    if method == "tools/call":
        p, a = req.get("params", {}), req.get("params", {}).get("arguments", {})
        code, body = do_post(name, a.get("text"), a.get("kind", "question")) if p.get("name") == "post_message" \
            else do_replies(name, int(a.get("since_id") or 0)) if p.get("name") == "read_replies" else (404, {"error": "no such tool"})
        return ok({"content": [{"type": "text", "text": json.dumps(body)}], "isError": code != 200})
    if rid is None:
        return None                                   # a notification: no reply
    return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "method not found"}}


class Handler(BaseHTTPRequestHandler):
    server_version = "sysmedic-hospital"

    def log_message(self, fmt, *a):
        sys.stderr.write("%s %s\n" % (self.log_date_time_string(), fmt % a))

    def send(self, code, body, ctype="application/json"):
        data = json.dumps(body).encode() if not isinstance(body, bytes) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def auth(self):
        a = self.headers.get("Authorization", "")
        name = who(a[7:]) if a.startswith("Bearer ") else None
        if not name:
            time.sleep(1)                             # slows guessing
            self.send(401, {"error": "unknown or revoked token"})
        return name

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/health":
            return self.send(200, {"ok": True})
        if u.path == "/client":                       # the rescue-side program, for machines not yet deployed with it (no secrets in it)
            return self.send(200, CLIENT.read_bytes(), "text/x-python")
        name = self.auth()
        if name and u.path == "/api/replies":
            code, body = do_replies(name, int((parse_qs(u.query).get("since") or ["0"])[0] or 0))
            self.send(code, body)
        elif name:
            self.send(404, {"error": "not found"})

    def do_POST(self):
        name = self.auth()
        if not name:
            return
        n = int(self.headers.get("Content-Length") or 0)
        if n > 64000:
            return self.send(413, {"error": "too large"})
        try:
            req = json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return self.send(400, {"error": "bad JSON"})
        u = urlparse(self.path)
        if u.path == "/api/post":
            code, body = do_post(name, req.get("text"), req.get("kind", "question"))
            self.send(code, body)
        elif u.path == "/mcp":
            r = mcp(name, req)
            self.send(202, b"") if r is None else self.send(200, r)
        else:
            self.send(404, {"error": "not found"})


def main():
    DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(DIR, 0o700)
    host, port = os.environ.get("MAILBOX_HOST", "0.0.0.0"), int(os.environ.get("MAILBOX_PORT", "8470"))
    cert, key = DIR / "cert.pem", DIR / "key.pem"
    if not cert.exists():
        os.system(f"openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -keyout {key} -out {cert} -subj /CN=sysmedic-hospital 2>/dev/null")
        os.chmod(key, 0o600)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(cert, key)
    srv = ThreadingHTTPServer((host, port), Handler)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    print(f"hospital listening on https://{host}:{port}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
