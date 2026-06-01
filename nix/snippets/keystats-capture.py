#!/usr/bin/env python3
import asyncio
import glob
import math
import os
import re
import select
import signal
import sys
import threading
import time
from collections import defaultdict
from pathlib import Path

import evdev
import sqlcipher3

DB_PATH = Path(os.environ["KEYSTATS_DB_PATH"])
DB_KEY_FILE = Path(os.environ["KEYSTATS_DB_KEY_FILE"])
HYPR_SOCK_ENV = os.environ.get("KEYSTATS_HYPRLAND_SOCK", "").strip()
DEVICE_NAME = "keyd virtual keyboard"
FLUSH_INTERVAL = 60
KEY_SPACE = evdev.ecodes.KEY_SPACE

TEXT_DB_KEY_FILE = os.environ.get("KEYSTATS_TEXT_DB_KEY_FILE", "").strip()
TEXT_DB_PATH = os.environ.get("KEYSTATS_TEXT_DB_PATH", "").strip()
TEXT_ALLOWLIST = {
    c.strip() for c in os.environ.get("KEYSTATS_TEXT_ALLOWLIST", "").split(",") if c.strip()
}
TEXT_BLACKLIST_FILE = os.environ.get("KEYSTATS_TEXT_BLACKLIST_FILE", "").strip()
TEXT_ENABLED = bool(TEXT_DB_KEY_FILE and TEXT_DB_PATH)
TEXT_ALLOW_ALL = len(TEXT_ALLOWLIST) == 0


def load_user_blacklist() -> set:
    if not TEXT_BLACKLIST_FILE:
        return set()
    p = Path(TEXT_BLACKLIST_FILE)
    if not p.exists():
        return set()
    out = set()
    for line in p.read_text(errors="replace").splitlines():
        s = line.strip().lower()
        if s and not s.startswith("#"):
            out.add(s)
    return out


USER_BLACKLIST = load_user_blacklist()

WORD_RACE_WINDOW = 0.25
WORD_MIN_LEN = 4
WORD_MAX_LEN = 12
WORD_ENTROPY_MAX = 3.5
WORD_MIN_OCCURRENCES = 5
WORD_MIN_DAYS = 3
CANDIDATE_CAP = 5000

SHAPE_BLOCK_RE = re.compile(
    r"\d{3}|"
    r"^[a-z0-9]{16,}$|"
    r"(?:com|net|org|io|dev|app|cc|br|co)$"
)

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
    r"(?i)password|passphrase|login|sign[- ]in|authenticate|unlock|otp|2fa|verification|sudo|"
    r"senha|entrar|cadastro|verificação|código|autenticar"
)

LETTER_MAP = {
    16: "q", 17: "w", 18: "e", 19: "r", 20: "t", 21: "y", 22: "u", 23: "i", 24: "o", 25: "p",
    30: "a", 31: "s", 32: "d", 33: "f", 34: "g", 35: "h", 36: "j", 37: "k", 38: "l",
    44: "z", 45: "x", 46: "c", 47: "v", 48: "b", 49: "n", 50: "m",
    40: "'",
}
KEY_BACKSPACE = 14
KEY_ENTER = 28
KEY_TAB = 15
WORD_BREAKERS = {
    KEY_SPACE, KEY_ENTER, KEY_TAB,
    51, 52, 53, 26, 27, 39, 41, 43,
    103, 105, 106, 108, 102, 107, 104, 109,
}
SHIFT_KEYS = {42, 54}

STOP_WORDS = {
    "the", "and", "for", "are", "but", "not", "you", "all", "can", "had", "her", "was", "one",
    "our", "out", "day", "get", "has", "him", "his", "how", "man", "new", "now", "old", "see",
    "two", "way", "who", "boy", "did", "its", "let", "put", "say", "she", "too", "use", "with",
    "this", "that", "have", "from", "they", "want", "been", "your", "were", "said", "each",
    "which", "their", "what", "about", "would", "there", "could", "other", "more", "than",
    "then", "them", "into", "some", "make", "like", "time", "just", "know", "take", "year",
    "good", "back", "after", "work", "first", "well", "even", "want", "because", "any", "these",
    "give", "most", "para", "com", "uma", "isso", "mais", "como", "isso", "essa", "esse",
    "ele", "ela", "nao", "que", "tem", "esta", "estao", "esses", "essas", "este", "neste",
    "nesta", "isso", "aquele", "aquela", "pelo", "pela", "voce", "vocs", "voces", "tudo",
    "nada", "muito", "pouco", "agora", "depois", "antes", "ainda", "sempre", "nunca", "talvez",
    "porque", "sobre", "assim", "entao", "enquanto", "tambem", "porem", "outra", "outro",
    "outros", "outras", "alguns", "algumas", "aqui", "ali", "isto", "sera", "seria", "foi",
    "vai", "vou", "fez", "feito", "ser", "ter", "estar", "fazer", "dizer", "ver", "ir",
    "dar", "saber", "querer", "poder",
}


def shannon_entropy(s: str) -> float:
    if not s:
        return 0.0
    counts = defaultdict(int)
    for c in s:
        counts[c] += 1
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in counts.values())


def word_filtered(w: str) -> bool:
    if len(w) < WORD_MIN_LEN or len(w) > WORD_MAX_LEN:
        return True
    if not all(c.isalpha() or c == "'" for c in w):
        return True
    if w in STOP_WORDS:
        return True
    if shannon_entropy(w) > WORD_ENTROPY_MAX:
        return True
    if SHAPE_BLOCK_RE.search(w):
        return True
    for b in USER_BLACKLIST:
        if b in w:
            return True
    return False


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
        self.active_class_since = 0.0
        self.session_start = int(time.time())
        self.class_keystroke_counts = {}
        self.shift_down = False
        self.word_buf = []
        self.word_candidates = defaultdict(dict)
        self.word_persist_queue = {}
        self.word_dropped_filter = 0


def gated(s: State) -> str:
    if s.active_class in BLOCKED_CLASSES:
        return "class"
    if s.active_title and TITLE_BLOCK_RE.search(s.active_title):
        return "title"
    return ""


def text_gated(s: State, ts: float) -> bool:
    if not TEXT_ALLOW_ALL and s.active_class not in TEXT_ALLOWLIST:
        return True
    if s.active_class in BLOCKED_CLASSES:
        return True
    if ts - s.active_class_since < WORD_RACE_WINDOW:
        return True
    if TITLE_BLOCK_RE.search(s.active_title or ""):
        return True
    return False


def load_key() -> str:
    raw = DB_KEY_FILE.read_text().strip()
    if not re.fullmatch(r"[0-9a-fA-F]{64}", raw):
        sys.exit(f"keystats: db key at {DB_KEY_FILE} must be 64 hex chars")
    return raw


def load_text_key() -> str:
    raw = Path(TEXT_DB_KEY_FILE).read_text().strip()
    if not re.fullmatch(r"[0-9a-fA-F]{64}", raw):
        sys.exit(f"keystats: text db key at {TEXT_DB_KEY_FILE} must be 64 hex chars")
    return raw


def open_text_db(key_hex: str):
    p = Path(TEXT_DB_PATH)
    p.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlcipher3.connect(str(p), check_same_thread=False)
    cur = conn.cursor()
    cur.execute(f"PRAGMA key = \"x'{key_hex}'\"")
    cur.execute("PRAGMA cipher_compatibility = 4")
    cur.execute("PRAGMA journal_mode = WAL")
    cur.execute("PRAGMA synchronous = NORMAL")
    cur.executescript(
        """
        CREATE TABLE IF NOT EXISTS word_count(
          word TEXT PRIMARY KEY,
          count INTEGER NOT NULL,
          last_seen INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS word_candidate(
          word TEXT NOT NULL,
          day  INTEGER NOT NULL,
          count INTEGER NOT NULL,
          PRIMARY KEY(word, day)
        );
        """
    )
    conn.commit()
    return conn


def open_db(key_hex: str):
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlcipher3.connect(str(DB_PATH), check_same_thread=False)
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
                if event.code in SHIFT_KEYS:
                    if event.value == 1:
                        state.shift_down = True
                    elif event.value == 0:
                        state.shift_down = False
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


def finalize_word(state: State, ts: float) -> None:
    if not state.word_buf:
        return
    word = "".join(state.word_buf).lower()
    state.word_buf.clear()
    if word_filtered(word):
        state.word_dropped_filter += 1
        return
    day = int(ts // 86400)
    days = state.word_candidates[word]
    days[day] = days.get(day, 0) + 1
    total = sum(days.values())
    if total >= WORD_MIN_OCCURRENCES and len(days) >= WORD_MIN_DAYS:
        state.word_persist_queue[word] = state.word_persist_queue.get(word, 0) + total
        del state.word_candidates[word]
    if len(state.word_candidates) > CANDIDATE_CAP:
        for k in list(state.word_candidates.keys())[:CANDIDATE_CAP // 4]:
            del state.word_candidates[k]


def on_keystroke(state: State, keycode: int, ts: float) -> None:
    with state.lock:
        if gated(state):
            state.dropped += 1
            state.last_key = None
            state.word_buf.clear()
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

        if not TEXT_ENABLED:
            return
        if text_gated(state, ts):
            state.word_buf.clear()
            return
        if keycode == KEY_BACKSPACE:
            if state.word_buf:
                state.word_buf.pop()
            return
        if keycode in WORD_BREAKERS:
            finalize_word(state, ts)
            return
        ch = LETTER_MAP.get(keycode)
        if ch is None:
            finalize_word(state, ts)
            return
        if len(state.word_buf) >= WORD_MAX_LEN + 4:
            state.word_buf.clear()
            return
        state.word_buf.append(ch)


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
            state.active_class_since = time.time()
            state.word_buf.clear()
    elif name == "activewindowv2":
        pass
    elif name == "closewindow":
        pass


def flush_loop(state: State, stop: threading.Event, conn) -> None:
    while not stop.wait(FLUSH_INTERVAL):
        try:
            flush(state, conn)
        except Exception as e:
            print(f"keystats: flush error: {e}", file=sys.stderr)


def load_candidates(state: State, text_conn) -> None:
    cur = text_conn.cursor()
    rows = cur.execute("SELECT word, day, count FROM word_candidate").fetchall()
    cutoff_day = int(time.time() // 86400) - 30
    stale = 0
    with state.lock:
        for w, d, c in rows:
            if d < cutoff_day:
                stale += 1
                continue
            state.word_candidates[w][d] = c
    if stale:
        cur.execute("DELETE FROM word_candidate WHERE day < ?", (cutoff_day,))
        text_conn.commit()


def text_flush(state: State, text_conn) -> None:
    with state.lock:
        queue = state.word_persist_queue
        dropped = state.word_dropped_filter
        candidates = {w: dict(d) for w, d in state.word_candidates.items()}
        state.word_persist_queue = {}
        state.word_dropped_filter = 0
    if not queue and dropped == 0 and not candidates:
        return
    now = int(time.time())
    cur = text_conn.cursor()
    for word, c in queue.items():
        cur.execute(
            "INSERT INTO word_count(word, count, last_seen) VALUES(?, ?, ?) "
            "ON CONFLICT(word) DO UPDATE SET count = count + excluded.count, last_seen = excluded.last_seen",
            (word, c, now),
        )
        cur.execute("DELETE FROM word_candidate WHERE word = ?", (word,))
    for word, days in candidates.items():
        for day, c in days.items():
            cur.execute(
                "INSERT INTO word_candidate(word, day, count) VALUES(?, ?, ?) "
                "ON CONFLICT(word, day) DO UPDATE SET count = excluded.count",
                (word, day, c),
            )
    text_conn.commit()
    print(
        f"keystats: text flush new_words={len(queue)} total_increments={sum(queue.values())} "
        f"candidates={len(candidates)} dropped_by_filter={dropped}",
        file=sys.stderr,
    )


def text_flush_loop(state: State, stop: threading.Event, text_conn) -> None:
    while not stop.wait(FLUSH_INTERVAL):
        try:
            text_flush(state, text_conn)
        except Exception as e:
            print(f"keystats: text flush error: {e}", file=sys.stderr)


def main() -> None:
    key_hex = load_key()
    conn = open_db(key_hex)
    text_conn = None
    if TEXT_ENABLED:
        text_conn = open_text_db(load_text_key())
        allow_desc = "ALL" if TEXT_ALLOW_ALL else sorted(TEXT_ALLOWLIST)
        print(
            f"keystats: text capture enabled allowlist={allow_desc} "
            f"blacklist_entries={len(USER_BLACKLIST)} db={TEXT_DB_PATH}",
            file=sys.stderr,
        )
    state = State()
    if text_conn is not None:
        load_candidates(state, text_conn)
    stop = threading.Event()

    def shutdown(*_):
        stop.set()
        try:
            flush(state, conn)
        except Exception:
            pass
        if text_conn is not None:
            try:
                text_flush(state, text_conn)
            except Exception:
                pass
            try:
                text_conn.close()
            except Exception:
                pass
        conn.close()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    threading.Thread(target=evdev_loop, args=(state, stop), daemon=True).start()
    threading.Thread(target=flush_loop, args=(state, stop, conn), daemon=True).start()
    if text_conn is not None:
        threading.Thread(target=text_flush_loop, args=(state, stop, text_conn), daemon=True).start()
    asyncio.run(hypr_loop(state, stop))


if __name__ == "__main__":
    main()
