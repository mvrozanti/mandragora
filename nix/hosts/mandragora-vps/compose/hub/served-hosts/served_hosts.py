import json
import os
import re
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ADMIN = os.environ.get("CADDY_ADMIN", "http://localhost:2019/config/")
PORT = int(os.environ.get("SERVED_HOSTS_PORT", "2020"))
HOST_RE = re.compile(r"^[a-z0-9-]+\.mvr\.ac$")


def served() -> list:
    with urllib.request.urlopen(ADMIN, timeout=5) as r:
        cfg = json.load(r)
    out = {}
    servers = cfg.get("apps", {}).get("http", {}).get("servers", {})
    for srv in servers.values():
        for route in srv.get("routes", []):
            hosts = [h for m in route.get("match", []) for h in m.get("host", [])]
            gated = "forward_auth" in json.dumps(route) or '"handler": "authentication"' in json.dumps(route)
            for h in hosts:
                if HOST_RE.match(h):
                    out[h] = out.get(h, False) or gated
    return [{"host": h, "gated": g} for h, g in sorted(out.items())]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path.split("?")[0].rstrip("/") != "/hosts":
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        try:
            body = json.dumps({"hosts": served()}).encode()
            code = 200
        except Exception as e:
            body = json.dumps({"error": str(e)}).encode()
            code = 503
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a) -> None:
        return


ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
