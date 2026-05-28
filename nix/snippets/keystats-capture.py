#!/usr/bin/env python3
import asyncio
import glob
import os
import re
import select
import signal
import socket
import sys
import threading
import time
from pathlib import Path

import evdev
import sqlcipher3

DB_PATH = Path(os.environ["KEYSTATS_DB_PATH"])
DB_KEY_FILE = Path(os.environ["KEYSTATS_DB_KEY_FILE"])
PAM_SOCK = Path(os.environ["KEYSTATS_PAM_SOCK"])
HYPR_SOCK_ENV = os.environ.get("KEYSTATS_HYPRLAND_SOCK", "").strip()
DEVICE_NAME = "keyd virtual keyboard"
FLUSH_INTERVAL = 60
KEY_SPACE = evdev.ecodes.KEY_SPACE

BLOCKED_CLASSES = {
    "hyprland-polkit-agent",
    "polkit-gnome-authentication-agent-1",
    "polkit-kde-authentication-agent-1",
    "gcr-prompter",
    "Bitwarden",
    "bitwarden",
    "org.keepassxc.KeePassXC",
    "keepassxc",
    "1Password",
}
TITLE_BLOCK_RE = re.compile(
    r"(?i)password|passphrase|login|sign[- ]in|authenticate|unlock|otp|2fa|verification|sudo"
)


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.keycode_counts = {}
        self.bigram_counts = {}
        self.wpm_buckets = {}
        self.dropped = 0
        self.last_key = None
        self.last_key_time = 0.0
        self.active_class = ""
        self.active_title = ""
        self.paused = False
        self.session_start = int(time.time())
        self.class_keystroke_counts = {}


def gated(s: State) -> str:
    if s.paused:
        return "pam"
    if s.active_class in BLOCKED_CLASSES:
        return "class"
    if s.active_title and TITLE_BLOCK_RE.search(s.active_title):
        return "title"
    return ""


def load_key() -> str:
    raw = DB_KEY_FILE.read_text().strip()
    if not re.fullmatch(r"[0-9a-fA-F]{64}", raw):
        sys.exit(f"keystats: db key at {DB_KEY_FILE} must be 64 hex chars")
    return raw


def open_db(key_hex: str):
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlcipher3.connect(str(DB_PATH))
    cur = conn.cursor()
    cur.execute(f"PRAGMA key = \"x'{key_hex}'\"")
    cur.execute("PRAGMA cipher_compatibility = 4")
    cur.execute("PRAGMA journal_mode = WAL")
    cur.execute("PRAGMA synchronous = NORMAL")
    cur.executescript(
        """
        CREATE TABLE IF NOT EXISTS keycode_count(
          keycode INTEGER PRIMARY KEY,
          count   INTEGER NOT NULL,
          last_seen INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS bigram_count(
          k1 INTEGER NOT NULL,
          k2 INTEGER NOT NULL,
          count INTEGER NOT NULL,
          PRIMARY KEY(k1, k2)
        );
        CREATE TABLE IF NOT EXISTS wpm_bucket(
          minute_epoch INTEGER PRIMARY KEY,
          chars INTEGER NOT NULL,
          words INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS class_count(
          window_class TEXT PRIMARY KEY,
          count INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS session(
          start_epoch INTEGER PRIMARY KEY,
          end_epoch   INTEGER NOT NULL,
          dropped     INTEGER NOT NULL
        );
        """
    )
    conn.commit()
    return conn


def flush(state: State, conn) -> None:
    with state.lock:
        kc = state.keycode_counts
        bg = state.bigram_counts
        wp = state.wpm_buckets
        cc = state.class_keystroke_counts
        dropped = state.dropped
        state.keycode_counts = {}
        state.bigram_counts = {}
        state.wpm_buckets = {}
        state.class_keystroke_counts = {}
        state.dropped = 0
        session_start = state.session_start
    now = int(time.time())
    cur = conn.cursor()
    for k, c in kc.items():
        cur.execute(
            "INSERT INTO keycode_count(keycode, count, last_seen) VALUES(?, ?, ?) "
            "ON CONFLICT(keycode) DO UPDATE SET count = count + excluded.count, last_seen = excluded.last_seen",
            (k, c, now),
        )
    for (k1, k2), c in bg.items():
        cur.execute(
            "INSERT INTO bigram_count(k1, k2, count) VALUES(?, ?, ?) "
            "ON CONFLICT(k1, k2) DO UPDATE SET count = count + excluded.count",
            (k1, k2, c),
        )
    for m, (chars, words) in wp.items():
        cur.execute(
            "INSERT INTO wpm_bucket(minute_epoch, chars, words) VALUES(?, ?, ?) "
            "ON CONFLICT(minute_epoch) DO UPDATE SET chars = chars + excluded.chars, words = words + excluded.words",
            (m, chars, words),
        )
    for cls, c in cc.items():
        cur.execute(
            "INSERT INTO class_count(window_class, count) VALUES(?, ?) "
            "ON CONFLICT(window_class) DO UPDATE SET count = count + excluded.count",
            (cls, c),
        )
    cur.execute(
        "INSERT INTO session(start_epoch, end_epoch, dropped) VALUES(?, ?, ?) "
        "ON CONFLICT(start_epoch) DO UPDATE SET end_epoch = excluded.end_epoch, dropped = session.dropped + excluded.dropped",
        (session_start, now, dropped),
    )
    conn.commit()


def find_keyd_device() -> str:
    for path in evdev.list_devices():
        try:
            d = evdev.InputDevice(path)
        except OSError:
            continue
        if d.name == DEVICE_NAME:
            d.close()
            return path
        d.close()
    return ""


def evdev_loop(state: State, stop: threading.Event) -> None:
    device_path = ""
    while not stop.is_set():
        if not device_path or not Path(device_path).exists():
            device_path = find_keyd_device()
            if not device_path:
                time.sleep(2)
                continue
        try:
            dev = evdev.InputDevice(device_path)
        except OSError as e:
            print(f"keystats: open {device_path}: {e}", file=sys.stderr)
            device_path = ""
            time.sleep(2)
            continue
        try:
            for event in dev.read_loop():
                if stop.is_set():
                    break
                if event.type != evdev.ecodes.EV_KEY:
                    continue
                if event.value != 1:
                    continue
                on_keystroke(state, event.code, event.timestamp())
        except OSError:
            device_path = ""
            time.sleep(1)
        finally:
            try:
                dev.close()
            except Exception:
                pass


def on_keystroke(state: State, keycode: int, ts: float) -> None:
    with state.lock:
        if gated(state):
            state.dropped += 1
            state.last_key = None
            return
        state.keycode_counts[keycode] = state.keycode_counts.get(keycode, 0) + 1
        if state.last_key is not None and ts - state.last_key_time < 2.0:
            bg = (state.last_key, keycode)
            state.bigram_counts[bg] = state.bigram_counts.get(bg, 0) + 1
        state.last_key = keycode
        state.last_key_time = ts
        minute = int(ts // 60)
        chars, words = state.wpm_buckets.get(minute, (0, 0))
        chars += 1
        if keycode == KEY_SPACE:
            words += 1
        state.wpm_buckets[minute] = (chars, words)
        if state.active_class:
            state.class_keystroke_counts[state.active_class] = (
                state.class_keystroke_counts.get(state.active_class, 0) + 1
            )


def hypr_socket_path() -> str:
    if HYPR_SOCK_ENV:
        return HYPR_SOCK_ENV
    uid = os.getuid()
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if his:
        p = f"/run/user/{uid}/hypr/{his}/.socket2.sock"
        if Path(p).exists():
            return p
    cands = sorted(glob.glob(f"/run/user/{uid}/hypr/*/.socket2.sock"))
    return cands[-1] if cands else ""


async def hypr_loop(state: State, stop: threading.Event) -> None:
    loop = asyncio.get_event_loop()
    while not stop.is_set():
        sock = hypr_socket_path()
        if not sock or not Path(sock).exists():
            await asyncio.sleep(2)
            continue
        try:
            reader, _ = await asyncio.open_unix_connection(sock)
        except (OSError, ConnectionRefusedError):
            await asyncio.sleep(2)
            continue
        try:
            while not stop.is_set():
                line = await reader.readline()
                if not line:
                    break
                handle_hypr_event(state, line.decode(errors="replace").rstrip("\n"))
        except (asyncio.IncompleteReadError, OSError):
            pass
        await asyncio.sleep(1)


def handle_hypr_event(state: State, line: str) -> None:
    if ">>" not in line:
        return
    name, _, payload = line.partition(">>")
    if name == "activewindow":
        cls, _, title = payload.partition(",")
        with state.lock:
            state.active_class = cls
            state.active_title = title
    elif name == "activewindowv2":
        pass
    elif name == "closewindow":
        pass


def pam_loop(state: State, stop: threading.Event) -> None:
    try:
        PAM_SOCK.unlink()
    except FileNotFoundError:
        pass
    PAM_SOCK.parent.mkdir(parents=True, exist_ok=True)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(str(PAM_SOCK))
    os.chmod(PAM_SOCK, 0o660)
    s.listen(8)
    s.settimeout(1.0)
    while not stop.is_set():
        try:
            conn, _ = s.accept()
        except socket.timeout:
            continue
        except OSError:
            break
        with conn:
            try:
                data = conn.recv(64).decode(errors="replace").strip().lower()
            except OSError:
                continue
            with state.lock:
                if data == "pause":
                    state.paused = True
                elif data == "resume":
                    state.paused = False
    s.close()
    try:
        PAM_SOCK.unlink()
    except FileNotFoundError:
        pass


def flush_loop(state: State, stop: threading.Event, conn) -> None:
    while not stop.wait(FLUSH_INTERVAL):
        try:
            flush(state, conn)
        except Exception as e:
            print(f"keystats: flush error: {e}", file=sys.stderr)


def main() -> None:
    key_hex = load_key()
    conn = open_db(key_hex)
    state = State()
    stop = threading.Event()

    def shutdown(*_):
        stop.set()
        try:
            flush(state, conn)
        except Exception:
            pass
        conn.close()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    threading.Thread(target=evdev_loop, args=(state, stop), daemon=True).start()
    threading.Thread(target=pam_loop, args=(state, stop), daemon=True).start()
    threading.Thread(target=flush_loop, args=(state, stop, conn), daemon=True).start()
    asyncio.run(hypr_loop(state, stop))


if __name__ == "__main__":
    main()
