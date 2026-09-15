import json
import os
import shutil
import signal
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SOI = b"\xff\xd8"
EOI = b"\xff\xd9"

HOST = os.environ.get("KINDLE_CAM_HOST", "0.0.0.0")
PORT = int(os.environ.get("KINDLE_CAM_PORT", "6686"))
SOURCE = os.environ.get("KINDLE_CAM_SOURCE", "http://100.114.176.5:4747/video")
WIDTH = int(os.environ.get("KINDLE_CAM_WIDTH", "1272"))
HEIGHT = int(os.environ.get("KINDLE_CAM_HEIGHT", "1696"))
FPS = os.environ.get("KINDLE_CAM_FPS", "4")
QUALITY = os.environ.get("KINDLE_CAM_QUALITY", "6")
ROTATE = os.environ.get("KINDLE_CAM_ROTATE", "0")
RETRY_SECONDS = float(os.environ.get("KINDLE_CAM_RETRY", "5"))
STALE_SECONDS = float(os.environ.get("KINDLE_CAM_STALE", "15"))
FFMPEG = os.environ.get("FFMPEG", shutil.which("ffmpeg") or "ffmpeg")

TRANSPOSE = {"90": "transpose=1", "180": "transpose=1,transpose=1", "270": "transpose=2"}


def filter_chain():
    parts = []
    turn = TRANSPOSE.get(ROTATE)
    if turn:
        parts.append(turn)
    parts.append("scale=%d:%d:force_original_aspect_ratio=decrease" % (WIDTH, HEIGHT))
    parts.append("pad=%d:%d:(ow-iw)/2:(oh-ih)/2:color=white" % (WIDTH, HEIGHT))
    parts.append("format=gray")
    return ",".join(parts)


def input_args():
    if SOURCE.startswith(("http://", "https://")):
        return [
            "-reconnect", "1",
            "-reconnect_streamed", "1",
            "-reconnect_delay_max", "5",
            "-i", SOURCE,
        ]
    if SOURCE.startswith("rtsp://"):
        return ["-rtsp_transport", "tcp", "-i", SOURCE]
    if SOURCE.startswith("/dev/video"):
        return ["-f", "v4l2", "-i", SOURCE]
    if SOURCE.startswith(("testsrc", "smptebars", "color=")):
        return ["-re", "-f", "lavfi", "-i", SOURCE]
    return ["-i", SOURCE]


def ffmpeg_command():
    return (
        [FFMPEG, "-hide_banner", "-loglevel", "error", "-nostdin"]
        + input_args()
        + [
            "-an",
            "-r", FPS,
            "-vf", filter_chain(),
            "-f", "mjpeg",
            "-q:v", QUALITY,
            "-",
        ]
    )


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.frame = None
        self.frame_at = 0.0
        self.frames = 0
        self.error = None
        self.started = time.time()
        self.proc = None
        self.stop = threading.Event()

    def publish(self, frame):
        with self.lock:
            self.frame = frame
            self.frame_at = time.time()
            self.frames += 1
            self.error = None

    def fail(self, message):
        with self.lock:
            self.error = message

    def snapshot(self):
        with self.lock:
            age = time.time() - self.frame_at if self.frame_at else None
            return {
                "source": SOURCE,
                "size": "%dx%d" % (WIDTH, HEIGHT),
                "rotate": ROTATE,
                "fps": FPS,
                "frames": self.frames,
                "age": round(age, 2) if age is not None else None,
                "live": age is not None and age < STALE_SECONDS,
                "error": self.error,
                "uptime": round(time.time() - self.started, 1),
            }

    def latest(self):
        with self.lock:
            return self.frame


def split_frames(state, stdout):
    buf = bytearray()
    while not state.stop.is_set():
        chunk = stdout.read(65536)
        if not chunk:
            return
        buf += chunk
        while True:
            start = buf.find(SOI)
            if start < 0:
                buf.clear()
                break
            end = buf.find(EOI, start + 2)
            if end < 0:
                if start:
                    del buf[:start]
                break
            state.publish(bytes(buf[start : end + 2]))
            del buf[: end + 2]


def pump(state):
    while not state.stop.is_set():
        try:
            proc = subprocess.Popen(
                ffmpeg_command(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                bufsize=0,
            )
        except OSError as exc:
            state.fail("spawn: %s" % exc)
            state.stop.wait(RETRY_SECONDS)
            continue

        with state.lock:
            state.proc = proc

        try:
            split_frames(state, proc.stdout)
        except OSError as exc:
            state.fail("read: %s" % exc)

        proc.terminate()
        try:
            stderr = proc.communicate(timeout=5)[1]
        except subprocess.TimeoutExpired:
            proc.kill()
            stderr = b""

        with state.lock:
            state.proc = None

        if not state.stop.is_set():
            detail = stderr.decode("utf-8", "replace").strip().splitlines()
            state.fail(detail[-1] if detail else "source ended")
            state.stop.wait(RETRY_SECONDS)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    state = None

    def log_message(self, *args):
        return

    def _send(self, code, body, content_type):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path in ("/", "/frame.jpg", "/frame"):
            frame = self.state.latest()
            if frame is None:
                self._send(503, b"no frame yet\n", "text/plain; charset=utf-8")
                return
            self._send(200, frame, "image/jpeg")
            return
        if path == "/status":
            body = json.dumps(self.state.snapshot(), indent=2).encode() + b"\n"
            self._send(200, body, "application/json")
            return
        self._send(404, b"not found\n", "text/plain; charset=utf-8")


def main():
    state = State()
    Handler.state = state

    def shutdown(*_):
        state.stop.set()
        with state.lock:
            proc = state.proc
        if proc:
            proc.terminate()
        os._exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    threading.Thread(target=pump, args=(state,), daemon=True).start()
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
