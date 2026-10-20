#!/usr/bin/env python3
"""python3 tools/telemetry/test_hub.py — the hub's ingest rules and API, on a throwaway port."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 18471


def req(path, data=None):
    body = None if data is None else (data if isinstance(data, bytes) else json.dumps(data).encode())
    r = urllib.request.Request(f"http://127.0.0.1:{PORT}{path}", data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=5) as f:
            return f.status, f.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


class T(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.state = tempfile.mktemp(suffix=".json")
        cls.p = subprocess.Popen([sys.executable, os.path.join(HERE, "telemetry-hub.py"), "--host", "127.0.0.1", "--port", str(PORT), "--state", cls.state])
        for _ in range(50):
            try:
                if req("/health")[0] == 200:
                    return
            except OSError:
                time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        cls.p.terminate()
        cls.p.wait()
        if os.path.exists(cls.state):
            os.unlink(cls.state)

    def test_ingest_and_fleet(self):
        c, _ = req("/ingest", {"h": "BOX", "m": 40, "d": 95, "t": 90, "l": 9, "cpu": 4, "up": 5, "sv": ["ssh:22"], "evil": "<script>"})
        self.assertEqual(c, 200)
        time.sleep(2.1)
        f = json.loads(req("/api/fleet")[1])
        h = next(x for x in f["hosts"] if x["h"] == "BOX")
        self.assertEqual(h["state"], "up")
        self.assertNotIn("evil", h)
        self.assertEqual(len(h["flags"]), 3)       # disk, temperature, load
        self.assertEqual(json.loads(req("/api/host/BOX")[1])["h"], "BOX")

    def test_rejects_bad_records(self):
        time.sleep(2.1)
        self.assertEqual(req("/ingest", {"h": "../x"})[0], 400)
        time.sleep(2.1)
        self.assertEqual(req("/ingest", b"not json")[0], 400)
        self.assertEqual(req("/ingest", b"x" * 9000)[0], 413)
        self.assertEqual(req("/api/host/nobody")[0], 404)

    def test_page_and_state_file(self):
        self.assertIn(b"Fleet telemetry", req("/fleet")[1])
        time.sleep(2.1)
        req("/ingest", {"h": "SAVED", "m": 1})
        with open(self.state) as f:
            self.assertIn("SAVED", json.load(f))


if __name__ == "__main__":
    unittest.main()
