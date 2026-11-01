import datetime
import os
import signal
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, os.environ["FH6_TUNER_SHARE"])

from laps.recorder import LapRecorder
from telemetry.receiver import UDPReceiver

SESSIONS_ROOT = Path.home() / ".local/state/fh6-tuner/sessions"
HOST = "127.0.0.1"
PORT = 5301
RACE_OVER_AFTER_SECONDS = 3.0
MAX_BUFFERED_FRAMES = 60 * 60 * 20


def log(msg):
    sys.stderr.write(f"fh6-tuner-collect: {msg}\n")
    sys.stderr.flush()


class Collector:
    def __init__(self):
        self.lock = threading.Lock()
        self.recorder = None
        self.last_race_frame_at = 0.0

    def session_dir(self):
        return SESSIONS_ROOT / f"auto-{datetime.date.today().isoformat()}"

    def on_frame(self, frame):
        if not frame.is_race_on:
            return
        with self.lock:
            if self.recorder is None:
                self.recorder = LapRecorder(self.session_dir())
                log(f"race on, recording into {self.recorder.session_dir}")
            if self.recorder.feed(frame):
                log(f"saved lap {self.recorder._lap_count - 1:03d}")
            if len(self.recorder._current_lap) > MAX_BUFFERED_FRAMES:
                log("dropping an open run longer than 20 minutes: not lap data")
                self.recorder._current_lap = []
            self.last_race_frame_at = time.monotonic()

    def close_race(self):
        with self.lock:
            if self.recorder is None:
                return
            self.recorder.flush()
            log(f"race over, session {self.recorder.session_dir.name} closed")
            self.recorder = None

    def tick(self):
        if self.recorder is not None and time.monotonic() - self.last_race_frame_at > RACE_OVER_AFTER_SECONDS:
            self.close_race()


def main():
    SESSIONS_ROOT.mkdir(parents=True, exist_ok=True)
    collector = Collector()
    receiver = UDPReceiver(host=HOST, port=PORT)
    receiver.start(collector.on_frame)
    log(f"listening on udp {HOST}:{PORT}, laps go to {SESSIONS_ROOT}/auto-<date>/")
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    signal.signal(signal.SIGINT, lambda *_: stopping.set())
    while not stopping.is_set():
        collector.tick()
        stopping.wait(1.0)
    receiver.stop()
    collector.close_race()


if __name__ == "__main__":
    main()
