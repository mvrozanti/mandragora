import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
PUBLIC = os.path.join(ROOT, "public")
DATA_DIR = os.environ.get("FOOD_DATA_DIR", "/data")
LIST_PATH = os.path.join(DATA_DIR, "list.json")
CATALOG_PATH = os.path.join(DATA_DIR, "catalog.json")
PORT = int(os.environ.get("PORT", "8080"))

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".webmanifest": "application/manifest+json",
    ".png": "image/png",
    ".ico": "image/x-icon",
}


def read_list():
    try:
        with open(LIST_PATH, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"items": [], "updated": None}


def write_list(payload):
    os.makedirs(DATA_DIR, exist_ok=True)
    tmp = LIST_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, LIST_PATH)


class Handler(BaseHTTPRequestHandler):
    server_version = "food/1.0"
    protocol_version = "HTTP/1.1"

    def _send(self, code, body=b"", ctype="application/json; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"))

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            return self._send(200, b"ok", "text/plain; charset=utf-8")
        if path == "/api/list":
            return self._json(200, read_list())
        if path == "/catalog.json":
            return self._serve_catalog()
        return self._serve_static(path)

    def do_PUT(self):
        if self.path.split("?", 1)[0] != "/api/list":
            return self._json(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return self._json(400, {"error": "invalid json"})
        if not isinstance(payload, dict) or not isinstance(payload.get("items"), list):
            return self._json(400, {"error": "expected {items: [...]}"})
        write_list(payload)
        return self._json(200, payload)

    do_POST = do_PUT

    def _serve_catalog(self):
        try:
            with open(CATALOG_PATH, "rb") as fh:
                body = fh.read()
        except FileNotFoundError:
            return self._json(200, {"foods": []})
        self._send(200, body, "application/json; charset=utf-8")

    def _serve_static(self, path):
        if path == "/":
            path = "/index.html"
        target = os.path.normpath(os.path.join(PUBLIC, path.lstrip("/")))
        if not target.startswith(PUBLIC) or not os.path.isfile(target):
            return self._send(404, b"not found", "text/plain; charset=utf-8")
        ext = os.path.splitext(target)[1]
        with open(target, "rb") as fh:
            body = fh.read()
        self._send(200, body, CONTENT_TYPES.get(ext, "application/octet-stream"))

    def log_message(self, *args):
        pass


def main():
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
