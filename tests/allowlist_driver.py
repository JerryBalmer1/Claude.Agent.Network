"""Drives mitmdump + allowlist.py against a local target; run inside the mitmproxy image with --network none.

    docker run --rm --network none --entrypoint python3 \
        -v <repo>/src/addons:/addons:ro -v <repo>/tests:/tests:ro -v <out>:/out \
        mitmproxy/mitmproxy:<tag> /tests/allowlist_driver.py

Writes /out/flows.mitm (the stream file, for ConvertTo-NetworkCapture) and /out/client.json (what the client saw).
"""
import http.server
import json
import os
import socket
import subprocess
import sys
import threading
import time

PROXY = ("127.0.0.1", 8080)
TARGET_PORT = 8000

sys.path.insert(0, "/addons")
from allowlist import parse_allowed_hosts  # noqa: E402


class Target(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"target ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def raw(request: bytes) -> dict:
    """Send one raw request to the proxy; return status and body."""
    with socket.create_connection(PROXY, 5) as s:
        s.sendall(request)
        s.settimeout(10)
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        head, _, body = data.partition(b"\r\n\r\n")
        length = next((int(l.split(b":", 1)[1]) for l in head.split(b"\r\n") if l.lower().startswith(b"content-length:")), 0)
        while len(body) < length:
            chunk = s.recv(65536)
            if not chunk:
                break
            body += chunk
    status = int(head.split(b" ", 2)[1]) if head else None
    return {"status": status, "body": body.decode("utf-8", "replace")}


def main():
    threading.Thread(target=http.server.HTTPServer(("127.0.0.1", TARGET_PORT), Target).serve_forever, daemon=True).start()

    env = dict(os.environ, ALLOWED_HOSTS="127.0.0.1, API.anthropic.com")
    proxy = subprocess.Popen(
        ["mitmdump", "--listen-host", PROXY[0], "--listen-port", str(PROXY[1]), "--set", "confdir=/tmp/ca",
         "-s", "/addons/allowlist.py", "--save-stream-file", "/out/flows.mitm"],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    try:
        for _ in range(100):
            try:
                socket.create_connection(PROXY, 1).close()
                break
            except OSError:
                time.sleep(0.1)
        results = {
            "defaultAllowed": sorted(parse_allowed_hosts(None)),
            "blankAllowed": sorted(parse_allowed_hosts(" , ")),
            "allowedPlain": raw(f"GET http://127.0.0.1:{TARGET_PORT}/ HTTP/1.1\r\nHost: 127.0.0.1:{TARGET_PORT}\r\n\r\n".encode()),
            "deniedPlain": raw(b"GET http://denied.example/ HTTP/1.1\r\nHost: denied.example\r\n\r\n"),
            "spoofedHost": raw(f"GET http://127.0.0.1:{TARGET_PORT}/ HTTP/1.1\r\nHost: evil.example\r\n\r\n".encode()),
            "deniedConnect": raw(b"CONNECT denied-tls.example:443 HTTP/1.1\r\nHost: denied-tls.example:443\r\n\r\n"),
            # Listed (case-insensitively) but unreachable with --network none: not refused, the upstream just fails.
            "allowedConnect": raw(b"CONNECT api.anthropic.com:443 HTTP/1.1\r\nHost: api.anthropic.com:443\r\n\r\n"),
        }
    finally:
        proxy.terminate()  # flushes the stream file
        log = proxy.communicate(timeout=30)[0].decode("utf-8", "replace")
    results["proxyLog"] = log
    with open("/out/client.json", "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)


main()
