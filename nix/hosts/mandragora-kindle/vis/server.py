#!/usr/bin/env python3
import io
import math
import os
import select
import socket
import socketserver
import sys
import threading
import time

import numpy as np
from PIL import Image

FIFO = os.environ.get("MPD_VIS_FIFO", "/tmp/mpd.fifo")
BIND = os.environ.get("MPD_VIS_BIND", "0.0.0.0")
PORT = int(os.environ.get("MPD_VIS_PORT", "6612"))
MPD_HOST = os.environ.get("MPD_VIS_MPD_HOST", "127.0.0.1")
MPD_PORT = int(os.environ.get("MPD_VIS_MPD_PORT", "6600"))
BANDS = int(os.environ.get("MPD_VIS_BANDS", "48"))
FPS = float(os.environ.get("MPD_VIS_FPS", "10"))
RATE = int(os.environ.get("MPD_VIS_RATE", "44100"))

CHANNELS = 2
FFT_SIZE = 2048
BLOCK_BYTES = FFT_SIZE * CHANNELS * 2
MAX_BACKLOG = BLOCK_BYTES * 6
LEVELS = 63
DB_FLOOR = -74.0
DB_SPAN_MIN = 30.0
SILENCE_AFTER = 0.45
REOPEN_AFTER = 5.0
COVER_MAX = 1024
GREYS = tuple(range(0, 256, 17))


def sigmoid_lut(contrast, mid):
    lo = 1.0 / (1.0 + math.exp(contrast * mid))
    hi = 1.0 / (1.0 + math.exp(contrast * (mid - 1.0)))
    span = hi - lo
    table = []
    for i in range(256):
        v = 1.0 / (1.0 + math.exp(contrast * (mid - i / 255.0)))
        table.append(int(max(0.0, min(1.0, (v - lo) / span)) * 255.0 + 0.5))
    return table


CONTRAST_LUT = sigmoid_lut(3.0, 0.5)


def grey_palette():
    pal = Image.new("P", (1, 1))
    entries = []
    for i in range(256):
        v = GREYS[i % len(GREYS)]
        entries += [v, v, v]
    pal.putpalette(entries)
    return pal


PALETTE = grey_palette()


class Analyser:
    def __init__(self):
        self.lock = threading.Lock()
        self.state = "X"
        self.frame = b"F" + b"X" + (b"0" * (BANDS * 2)) + b"\n"
        self._pending = np.zeros(BANDS, dtype=np.float64)
        self._bars = np.zeros(BANDS, dtype=np.float64)
        self._peaks = np.zeros(BANDS, dtype=np.float64)
        self._ceiling = DB_FLOOR + DB_SPAN_MIN
        self._window = np.hanning(FFT_SIZE).astype(np.float32)
        freqs = np.fft.rfftfreq(FFT_SIZE, 1.0 / RATE)
        edges = np.geomspace(35.0, min(16500.0, RATE / 2.0 - 1.0), BANDS + 1)
        lo = np.searchsorted(freqs, edges[:-1], side="left")
        hi = np.maximum(np.searchsorted(freqs, edges[1:], side="left"), lo + 1)
        self._slices = list(zip(lo.tolist(), hi.tolist()))
        centres = np.sqrt(edges[:-1] * edges[1:])
        self._tilt = np.clip(5.0 * np.log2(centres / 150.0), 0.0, 28.0)

    def read_loop(self):
        fd = None
        tail = b""
        last_audio = 0.0
        while True:
            if fd is None:
                fd = self._open()
                if fd is None:
                    self._set_state("X")
                    time.sleep(1.0)
                    continue
                tail = b""
                last_audio = time.monotonic()
            try:
                ready, _, _ = select.select([fd], [], [], 0.05)
            except OSError:
                os.close(fd)
                fd = None
                continue
            chunk = b""
            if ready:
                try:
                    chunk = os.read(fd, 1 << 16)
                except BlockingIOError:
                    chunk = b""
                except OSError:
                    os.close(fd)
                    fd = None
                    continue
            if chunk:
                last_audio = time.monotonic()
                self._set_state("L")
                tail = self._consume(tail + chunk)
            else:
                idle = time.monotonic() - last_audio
                if idle > SILENCE_AFTER:
                    self._set_state("S")
                    tail = b""
                if idle > REOPEN_AFTER and self._stale(fd):
                    os.close(fd)
                    fd = None

    def _open(self):
        try:
            return os.open(FIFO, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            return None

    def _stale(self, fd):
        try:
            held = os.fstat(fd)
            live = os.stat(FIFO)
        except OSError:
            return True
        return (held.st_dev, held.st_ino) != (live.st_dev, live.st_ino)

    def _set_state(self, state):
        with self.lock:
            self.state = state

    def _consume(self, buf):
        if len(buf) > MAX_BACKLOG:
            drop = (len(buf) - MAX_BACKLOG) // 4 * 4
            buf = buf[drop:]
        while len(buf) >= BLOCK_BYTES:
            block = buf[:BLOCK_BYTES]
            buf = buf[BLOCK_BYTES:]
            samples = np.frombuffer(block, dtype="<i2").astype(np.float32)
            mono = (samples[0::2] + samples[1::2]) * (0.5 / 32768.0)
            spectrum = np.abs(np.fft.rfft(mono * self._window)) * (2.0 / FFT_SIZE)
            bands = np.empty(BANDS, dtype=np.float64)
            for i, (lo, hi) in enumerate(self._slices):
                bands[i] = spectrum[lo:hi].max()
            with self.lock:
                np.maximum(self._pending, bands, out=self._pending)
        return buf

    def tick_loop(self):
        period = 1.0 / FPS
        nxt = time.monotonic()
        while True:
            self._tick()
            nxt += period
            delay = nxt - time.monotonic()
            if delay < 0.0:
                nxt = time.monotonic()
                delay = 0.0
            time.sleep(delay)

    def _tick(self):
        with self.lock:
            raw = self._pending.copy()
            self._pending[:] = 0.0
            state = self.state
        if state == "L" and raw.max() > 0.0:
            db = 20.0 * np.log10(raw + 1e-12) + self._tilt
            top = float(db.max())
            self._ceiling = max(top, self._ceiling - 1.2, DB_FLOOR + DB_SPAN_MIN)
            norm = (db - DB_FLOOR) / max(self._ceiling - DB_FLOOR, DB_SPAN_MIN)
            target = np.clip(norm, 0.0, 1.0) * LEVELS
        else:
            target = np.zeros(BANDS, dtype=np.float64)
        rising = target > self._bars
        self._bars = np.where(
            rising,
            self._bars + (target - self._bars) * 0.70,
            self._bars + (target - self._bars) * 0.28,
        )
        self._peaks = np.maximum(self._peaks - 1.4, self._bars)
        bars = np.clip(self._bars + 0.5, 0, LEVELS).astype(np.uint8) + 48
        peaks = np.clip(self._peaks + 0.5, 0, LEVELS).astype(np.uint8) + 48
        frame = b"F" + state.encode() + bars.tobytes() + peaks.tobytes() + b"\n"
        with self.lock:
            self.frame = frame

    def snapshot(self):
        with self.lock:
            return self.frame


class Mpd:
    def __init__(self):
        self.sock = None
        self.stream = None

    def connect(self):
        self.close()
        sock = socket.create_connection((MPD_HOST, MPD_PORT), timeout=6)
        stream = sock.makefile("rb")
        if not stream.readline().startswith(b"OK MPD"):
            sock.close()
            raise OSError("unexpected banner")
        self.sock = sock
        self.stream = stream

    def close(self):
        if self.stream is not None:
            self.stream.close()
        if self.sock is not None:
            self.sock.close()
        self.sock = None
        self.stream = None

    def command(self, line):
        self.sock.sendall(line.encode("utf-8") + b"\n")
        out = {}
        while True:
            raw = self.stream.readline()
            if not raw:
                raise OSError("connection closed")
            if raw.startswith(b"OK"):
                return out
            if raw.startswith(b"ACK"):
                raise LookupError(raw.decode("utf-8", "replace").strip())
            key, _, value = raw.partition(b": ")
            out[key.decode("ascii", "replace")] = value.rstrip(b"\n").decode(
                "utf-8", "replace"
            )

    def picture(self, uri):
        quoted = uri.replace("\\", "\\\\").replace('"', '\\"')
        for verb in ("readpicture", "albumart"):
            data = self._picture_with(verb, quoted)
            if data:
                return data
        return None

    def _picture_with(self, verb, quoted):
        buf = bytearray()
        offset = 0
        total = None
        while True:
            self.sock.sendall(
                ('%s "%s" %d' % (verb, quoted, offset)).encode("utf-8") + b"\n"
            )
            chunk = None
            while True:
                raw = self.stream.readline()
                if not raw:
                    raise OSError("connection closed")
                if raw.startswith(b"ACK"):
                    return None
                if raw.startswith(b"OK"):
                    break
                if raw.startswith(b"size: "):
                    total = int(raw[6:])
                elif raw.startswith(b"binary: "):
                    want = int(raw[8:])
                    chunk = self.stream.read(want)
                    self.stream.read(1)
            if not chunk:
                break
            buf += chunk
            offset += len(chunk)
            if total is None or offset >= total or len(buf) > 12 << 20:
                break
        return bytes(buf) if buf else None


class Covers:
    def __init__(self):
        self.lock = threading.Lock()
        self.uri = None
        self.cache = {}
        self.mpd = Mpd()

    def poll_loop(self):
        while True:
            try:
                if self.mpd.sock is None:
                    self.mpd.connect()
                song = self.mpd.command("currentsong")
                uri = song.get("file")
                with self.lock:
                    if uri != self.uri:
                        self.uri = uri
                        self.cache.clear()
            except (OSError, LookupError):
                self.mpd.close()
            time.sleep(2.0)

    def png(self, size, uri=None):
        size = max(64, min(COVER_MAX, size))
        with self.lock:
            if uri:
                if uri != self.uri:
                    self.uri = uri
                    self.cache.clear()
            else:
                uri = self.uri
            if uri is None:
                return None
            if size in self.cache:
                return self.cache[size]
        data = None
        try:
            if self.mpd.sock is None:
                self.mpd.connect()
            data = self.mpd.picture(uri)
        except (OSError, LookupError):
            self.mpd.close()
        png = render_cover(data, size) if data else None
        with self.lock:
            if self.uri == uri:
                self.cache[size] = png
        return png


def render_cover(data, size):
    try:
        img = Image.open(io.BytesIO(data)).convert("L")
    except Exception:
        return None
    w, h = img.size
    if w < 1 or h < 1:
        return None
    scale = size / float(min(w, h))
    img = img.resize(
        (max(size, int(w * scale + 0.5)), max(size, int(h * scale + 0.5))),
        Image.LANCZOS,
    )
    w, h = img.size
    left = (w - size) // 2
    top = (h - size) // 2
    img = img.crop((left, top, left + size, top + size))
    img = img.point(CONTRAST_LUT)
    img = (
        img.convert("RGB")
        .quantize(palette=PALETTE, dither=Image.Dither.FLOYDSTEINBERG)
        .convert("L")
    )
    out = io.BytesIO()
    img.save(out, format="PNG", optimize=True)
    return out.getvalue()


class Handler(socketserver.StreamRequestHandler):
    timeout = 20

    def handle(self):
        try:
            self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        raw = self.rfile.readline(4096)
        if not raw:
            return
        parts = raw.decode("ascii", "replace").split()
        if not parts:
            return
        verb = parts[0].upper()
        if verb == "SUB":
            self.stream_frames()
        elif verb == "COVER":
            self.send_cover(parts)
        elif verb == "PING":
            self.wfile.write(b"PONG\n")

    def stream_frames(self):
        self.connection.settimeout(8)
        self.wfile.write(("VIS 1 %d %d\n" % (BANDS, int(FPS))).encode("ascii"))
        self.wfile.flush()
        period = 1.0 / FPS
        nxt = time.monotonic()
        while True:
            self.wfile.write(ANALYSER.snapshot())
            self.wfile.flush()
            nxt += period
            delay = nxt - time.monotonic()
            if delay < 0.0:
                nxt = time.monotonic()
                delay = 0.0
            time.sleep(delay)

    def send_cover(self, parts):
        self.connection.settimeout(20)
        try:
            size = int(parts[1])
        except (IndexError, ValueError):
            size = 440
        uri = " ".join(parts[2:]) if len(parts) > 2 else None
        png = COVERS.png(size, uri)
        if not png:
            self.wfile.write(b"NOCOVER\n")
            return
        self.wfile.write(("COVER %d\n" % len(png)).encode("ascii"))
        self.wfile.write(png)
        self.wfile.flush()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def handle_error(self, request, client_address):
        exc = sys.exc_info()[1]
        if isinstance(exc, (BrokenPipeError, ConnectionResetError, TimeoutError, socket.timeout)):
            return
        super().handle_error(request, client_address)


ANALYSER = Analyser()
COVERS = Covers()


def main():
    threading.Thread(target=ANALYSER.read_loop, daemon=True).start()
    threading.Thread(target=ANALYSER.tick_loop, daemon=True).start()
    threading.Thread(target=COVERS.poll_loop, daemon=True).start()
    Server((BIND, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
