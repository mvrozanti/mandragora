import json
import os
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
PUBLIC = os.path.join(ROOT, "public")
DATA_DIR = os.environ.get("FOOD_DATA_DIR", "/data")
LIST_PATH = os.path.join(DATA_DIR, "list.json")
INBOX_PATH = os.path.join(DATA_DIR, "inbox.json")
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
    write_json(LIST_PATH, payload)


def write_json(path, payload):
    os.makedirs(DATA_DIR, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def read_inbox():
    try:
        with open(INBOX_PATH, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"items": [], "updated": None}


def append_inbox(name, note):
    inbox = read_inbox()
    key = norm(name)
    if not key:
        return inbox
    for it in inbox["items"]:
        if norm(it.get("name")) == key:
            return inbox
    inbox["items"].append({"name": name.strip(), "note": (note or "").strip()})
    inbox["updated"] = None
    write_json(INBOX_PATH, inbox)
    return inbox


def norm(s):
    folded = unicodedata.normalize("NFD", (s or "").strip().lower())
    return "".join(c for c in folded if not unicodedata.combining(c))


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
        if path == "/api/inbox":
            return self._json(200, read_inbox())
        if path == "/catalog.json":
            return self._serve_catalog()
        return self._serve_static(path)

    def _body(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8"))

    def do_PUT(self):
        path = self.path.split("?", 1)[0]
        try:
            payload = self._body()
        except (ValueError, UnicodeDecodeError):
            return self._json(400, {"error": "invalid json"})
        if path == "/api/list":
            if not isinstance(payload, dict) or not isinstance(payload.get("items"), list):
                return self._json(400, {"error": "expected {items: [...]}"})
            write_list(payload)
            return self._json(200, payload)
        if path == "/api/inbox":
            if not isinstance(payload, dict) or not isinstance(payload.get("items"), list):
                return self._json(400, {"error": "expected {items: [...]}"})
            write_json(INBOX_PATH, payload)
            return self._json(200, payload)
        return self._json(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path == "/api/inbox":
            try:
                payload = self._body()
            except (ValueError, UnicodeDecodeError):
                return self._json(400, {"error": "invalid json"})
            if not isinstance(payload, dict) or not isinstance(payload.get("name"), str):
                return self._json(400, {"error": "expected {name: ...}"})
            return self._json(200, append_inbox(payload["name"], payload.get("note")))
        return self.do_PUT()

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
