#!/usr/bin/env python3
"""A fake publik for the CI layout check (ios-gate-layout-test.sh). Test builds only; never a release.

It answers like publik for one device:
  POST /api/v1/installs   a fake key for this device, and the claim page
  GET  /api/v1/wallet     "anonymous" until the claim page opens, then "claimed"
  GET  /claim             the page the in-app browser opens: it signs the device in
  POST anything else      200 (telemetry)
If the in-app browser never loads the page, the device is signed in 20 s after the first
wallet check anyway (the browser sheet is still open then, which is the case under test).
Usage: fake-publik.py <port>
"""
import json
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
BASE = f"http://127.0.0.1:{PORT}"
STATE = {"claimed": False, "first_wallet": None}
LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def send(self, status, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("content-length") or 0))
        if self.path.startswith("/api/v1/installs"):
            key = "pk_" + "cifake" + uuid.uuid4().hex  # a fake key, valid only on this fake publik
            return self.send(201, {"key": key, "install_id": str(uuid.uuid4()),
                                   "claim_url": BASE + "/claim", "base_url": BASE + "/api/v1"})
        return self.send(200, {"ok": True})

    def do_GET(self):
        if self.path.startswith("/claim"):
            with LOCK:
                STATE["claimed"] = True
            print("fake-publik: the in-app browser opened the claim page", flush=True)
            return self.send(200, "<!doctype html><meta name=viewport content='width=device-width'>"
                                  "<h1>Signed in (CI)</h1>", "text/html")
        if self.path.startswith("/api/v1/wallet"):
            with LOCK:
                now = time.time()
                if STATE["first_wallet"] is None:
                    STATE["first_wallet"] = now
                if not STATE["claimed"] and now - STATE["first_wallet"] > 20:
                    STATE["claimed"] = True
                    print("fake-publik: no claim page after 20 s; signed in anyway", flush=True)
                claimed = STATE["claimed"]
            return self.send(200, {"claim_state": "claimed" if claimed else "anonymous",
                                   "claim_url": BASE + "/claim",
                                   "account": {"handle": "ci"} if claimed else None,
                                   "plan": {"kind": "none"}, "balance_micros": 0,
                                   "top_up_url": BASE + "/wallet"})
        return self.send(404, {"error": {"type": "not_found", "message": "not found"}})

    def log_message(self, fmt, *args):
        print("fake-publik: " + (fmt % args), flush=True)


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
