"""Tiny localhost receiver for model exports.

The browser page POSTs exported .glb blobs here (instead of triggering a
download dialog). Files land in tools/incoming/<name>.
Usage: python -I tools/upload_server.py [port]
"""
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "incoming")
os.makedirs(OUT_DIR, exist_ok=True)


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Private-Network", "true")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self._cors()
        self.end_headers()
        self.wfile.write(b"\n".join(n.encode() for n in sorted(os.listdir(OUT_DIR))))

    def do_POST(self):
        q = parse_qs(urlparse(self.path).query)
        name = q.get("name", ["upload.bin"])[0]
        name = re.sub(r"[^A-Za-z0-9_.\-]", "_", name)
        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length)
        with open(os.path.join(OUT_DIR, name), "wb") as f:
            f.write(data)
        print(f"saved {name} ({len(data)} bytes)", flush=True)
        self.send_response(200)
        self._cors()
        self.end_headers()
        self.wfile.write(f"ok {len(data)}".encode())


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
