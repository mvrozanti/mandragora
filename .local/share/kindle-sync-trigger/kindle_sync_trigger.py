import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("KINDLE_SYNC_TRIGGER_HOST", "0.0.0.0")
PORT = int(os.environ.get("KINDLE_SYNC_TRIGGER_PORT", "6690"))


def _run():
    proc = subprocess.run(
        ["systemctl", "--user", "start", "kindle-sync"],
        capture_output=True, text=True, timeout=1800,
    )
    journal = subprocess.run(
        ["journalctl", "--user", "-u", "kindle-sync", "-n", "40", "--no-pager", "-o", "cat"],
        capture_output=True, text=True, timeout=30,
    )
    return {"ok": proc.returncode == 0, "output": (journal.stdout or "").strip()[-4000:]}


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/sync":
            self.send_error(404)
            return
        body = json.dumps(_run()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
