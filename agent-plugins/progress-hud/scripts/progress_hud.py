import glob
import hashlib
import json
import math
import os
import re
import shlex
import shutil
import sys
import time

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-Z\\-_]")
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")
TASK_OUTPUT = re.compile(r"/tasks/[^/]+\.output(?: \(deleted\))?$")
PERCENT = re.compile(r"(?<![\w.])(\d{1,3}(?:\.\d+)?)\s?%")
FRACTION = re.compile(r"(?<![\w/.:-])(\d+)\s?/\s?(\d+)(?![\w/.-])|(?<![\w.])(\d+) of (\d+)(?![\w.])")
CD_PREFIX = re.compile(r"cd\s+\S+\s*(?:&&|;)\s*")
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=\S*")
SUBCOMMAND = re.compile(r"[a-z][\w:.-]*")
DURATION = re.compile(r"\d+(?:\.\d+)?[smhd]?")
WRAPPERS = {"rtk", "sudo", "time", "nice", "nohup", "command", "exec", "env", "builtin", "stdbuf"}
CONNECTORS = {"&&", "||", ";"}
HEX = re.compile(r"#[0-9a-fA-F]{6}")

SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
EIGHTHS = " ▏▎▍▌▋▊▉"
RESET = "\x1b[0m"
DIM = "\x1b[2m"
TONE = {"parsed": "\x1b[32m", "estimate": "\x1b[36m", "over": "\x1b[33m", "unknown": "\x1b[35m"}

DEFAULT_ROWS = 3
DEFAULT_STYLE = "rise"
LINGER = 5
SIZE_SAMPLES = 240
TAIL_BYTES = 8192
TAIL_LINES = 8
MIN_ELAPSED = 1.5
MIN_RECORDED = 3.0
QUIET_AFTER = 30
HUD_MAX_AGE = 15
HUD_TIMEOUT = 3
HISTORY_SAMPLES = 7
FAMILY_SPREAD = 3
HISTORY_MAX_BYTES = 512 * 1024
HISTORY_KEEP = 2000


def state_dir(env, fallback):
    path = os.path.join(os.environ.get(env) or fallback, "progress-hud")
    os.makedirs(path, exist_ok=True)
    return path


def write_atomic(path, payload):
    tmp = f"{path}.{os.getpid()}"
    with open(tmp, "w") as f:
        f.write(payload)
    os.replace(tmp, path)


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def proc_stat(pid):
    with open(f"/proc/{pid}/stat") as f:
        data = f.read()
    close = data.rindex(")")
    rest = data[close + 2:].split()
    return data[data.index("(") + 1:close], int(rest[1]), int(rest[19])


def proc_argv(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return [a.decode("utf-8", "replace") for a in f.read().split(b"\0") if a]


def boot_time():
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("btime "):
                return int(line.split()[1])
    return 0


def is_claude(pid, comm):
    if comm == "claude":
        return True
    try:
        argv = proc_argv(pid)
    except OSError:
        return False
    return any(os.path.basename(a) in ("claude", "cli.js") for a in argv[:2])


def claude_ancestor():
    pid = os.getppid()
    for _ in range(8):
        if pid <= 1:
            return None
        try:
            comm, ppid, _ = proc_stat(pid)
        except OSError:
            return None
        if is_claude(pid, comm):
            return pid
        pid = ppid
    return None


def extract_command(argv):
    if len(argv) >= 3 and argv[1] == "-c":
        try:
            tokens = shlex.split(argv[2])
        except ValueError:
            tokens = []
        if "eval" in tokens:
            i = tokens.index("eval")
            if i + 1 < len(tokens):
                return tokens[i + 1]
        return argv[2]
    return " ".join(argv)


def normalize(command):
    original = " ".join(command.split())
    text = original
    while True:
        before = text
        if (m := CD_PREFIX.match(text)):
            text = text[m.end():]
        words = text.split(" ") if text else []
        if words and (ASSIGNMENT.fullmatch(words[0]) or words[0] in WRAPPERS or words[0] in CONNECTORS):
            words.pop(0)
        elif words and words[0] == "timeout" and len(words) > 1:
            words.pop(0)
            while words and (words[0].startswith("-") or DURATION.fullmatch(words[0])):
                words.pop(0)
        text = " ".join(words)
        if text == before:
            break
    return (text or original)[:200]


def family(key):
    words = key.split(" ")
    head = os.path.basename(words[0])
    if len(words) > 1 and SUBCOMMAND.fullmatch(words[1]):
        return f"{head} {words[1]}"
    return head


def output_lines(path):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(0, f.tell() - TAIL_BYTES))
            text = f.read().decode("utf-8", "replace")
    except OSError:
        return []
    clean = ANSI.sub("", text)
    return [CONTROL.sub("", s).strip() for s in re.split(r"[\r\n]+", clean) if s.strip()][-TAIL_LINES:]


def parse_match(lines):
    for line in reversed(lines):
        percents = [m for m in PERCENT.finditer(line) if float(m.group(1)) <= 100]
        if percents:
            m = percents[-1]
            return float(m.group(1)) / 100, m.group(0).replace(" ", ""), None
        ratios = []
        for m in FRACTION.finditer(line):
            done, total = (int(m.group(1)), int(m.group(2))) if m.group(1) else (int(m.group(3)), int(m.group(4)))
            if total >= 2 and done <= total:
                ratios.append((done / total, f"{done}/{total}", (done, total)))
        if ratios:
            return ratios[-1]
    return None


def parse_progress(lines):
    match = parse_match(lines)
    return match[0] if match else None


def children_of(owner):
    pids = []
    for tid in os.listdir(f"/proc/{owner}/task"):
        try:
            with open(f"/proc/{owner}/task/{tid}/children") as f:
                pids.extend(f.read().split())
        except OSError:
            continue
    return pids


def all_processes():
    return [name for name in os.listdir("/proc") if name.isdigit()]


def running_tasks(session):
    owner = claude_ancestor()
    pids = all_processes() if owner is None else children_of(owner)
    ticks = os.sysconf("SC_CLK_TCK")
    btime = boot_time()
    found = {}
    for name in pids:
        try:
            target = os.readlink(f"/proc/{name}/fd/1")
        except OSError:
            continue
        if not TASK_OUTPUT.search(target):
            continue
        try:
            _, ppid, start = proc_stat(name)
            argv = proc_argv(name)
        except OSError:
            continue
        mine = ppid == owner if owner is not None else f"/{session}/" in target
        if not mine:
            continue
        path = target.removesuffix(" (deleted)")
        began = btime + start / ticks
        if path in found and found[path]["start"] <= began:
            continue
        key = normalize(extract_command(argv))
        found[path] = {"pid": name, "out": path, "start": began, "key": key, "family": family(key)}
    return list(found.values())


def load_history(path):
    exact, families = {}, {}
    try:
        with open(path) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    key, group, duration = entry["k"], entry["f"], float(entry["d"])
                except (ValueError, KeyError, TypeError):
                    continue
                exact.setdefault(key, []).append(duration)
                families.setdefault(group, []).append(duration)
    except OSError:
        pass
    return exact, families


def median(samples):
    ordered = sorted(samples)
    mid = len(ordered) // 2
    return ordered[mid] if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2


def estimate_samples(task, exact, families):
    own = exact.get(task["key"])
    if own:
        recent = own[-HISTORY_SAMPLES:]
        return median(recent), recent
    kin = families.get(task["family"], [])[-HISTORY_SAMPLES:]
    if len(kin) >= 2 and max(kin) <= FAMILY_SPREAD * min(kin):
        return median(kin), kin
    return None, []


def estimate(task, exact, families):
    return estimate_samples(task, exact, families)[0]


def append_history(path, entries):
    with open(path, "a") as f:
        f.write("".join(json.dumps(e) + "\n" for e in entries))
    if os.path.getsize(path) > HISTORY_MAX_BYTES:
        with open(path) as f:
            kept = f.readlines()[-HISTORY_KEEP:]
        write_atomic(path, "".join(kept))


def file_size(path):
    try:
        return os.stat(path).st_size
    except OSError:
        return 0


def track(state_path, history_path, tasks, now, sizes=False):
    previous = read_json(state_path)
    if not isinstance(previous, dict):
        previous = {}
    seen_tasks = previous.get("tasks") if isinstance(previous.get("tasks"), dict) else {}
    alive = {t["pid"]: t for t in tasks}
    finished = []
    done = [d for d in previous.get("done", []) if isinstance(d, dict) and now - d.get("at", 0) < LINGER]
    for pid, seen in seen_tasks.items():
        current = alive.get(pid)
        if current and abs(current["start"] - seen["s"]) < 1:
            continue
        end = seen["l"]
        try:
            end = max(end, os.stat(seen["o"]).st_mtime)
        except OSError:
            pass
        duration = min(end, now) - seen["s"]
        if duration >= MIN_RECORDED:
            finished.append({"k": seen["k"], "f": seen["f"], "d": round(duration, 1), "t": int(now)})
            done.append({"key": seen["k"], "start": seen["s"], "duration": round(duration, 1), "at": now})
    if finished:
        append_history(history_path, finished)
    entries = {}
    for t in tasks:
        entry = {"s": t["start"], "l": now, "o": t["out"], "k": t["key"], "f": t["family"]}
        if sizes:
            old = seen_tasks.get(t["pid"]) or {}
            trail = old.get("z", []) if abs(old.get("s", 0) - t["start"]) < 1 else []
            entry["z"] = (trail + [[now, file_size(t["out"])]])[-SIZE_SAMPLES:]
            t["sizes"] = entry["z"]
        entries[t["pid"]] = entry
    if entries or seen_tasks or done or previous.get("done"):
        write_atomic(state_path, json.dumps({"tasks": entries, "done": done}))
    return done


def clock(seconds):
    s = int(max(seconds, 0))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s // 3600}h{s % 3600 // 60:02d}m"


def clip(text, width):
    if width <= 0:
        return ""
    return text if len(text) <= width else text[:width - 1] + "…"


def bar(fraction, width, tone):
    cells = min(max(fraction, 0.0), 1.0) * width
    full = int(cells)
    partial = int((cells - full) * 8) if full < width else 0
    used = full + (1 if partial else 0)
    head = "█" * full + (EIGHTHS[partial] if partial else "")
    return f"{tone}{head}{RESET}{DIM}{'░' * (width - used)}{RESET}"


def bounce(width, now, tone):
    size = min(3, width)
    span = max(width - size, 1)
    step = int(now * 2) % (2 * span)
    pos = step if step < span else 2 * span - step
    return f"{DIM}{'░' * pos}{RESET}{tone}{'█' * size}{RESET}{DIM}{'░' * (width - pos - size)}{RESET}"


def file_mtime(path, fallback):
    try:
        return os.stat(path).st_mtime
    except OSError:
        return fallback


def enrich(task, lines, mtime, exact, families):
    match = parse_match(lines)
    expected, samples = estimate_samples(task, exact, families)
    return {
        **task,
        "mtime": max(mtime, task["start"]),
        "last": lines[-1] if lines else "",
        "progress": match[0] if match else None,
        "src": match[1] if match else None,
        "ratio": match[2] if match else None,
        "estimate": expected,
        "samples": samples,
    }


def facts(task, now):
    elapsed = task["duration"] if task.get("done") else now - task["start"]
    expected = task.get("estimate")
    if task.get("done"):
        mode, fraction = "done", 1.0
    elif task.get("progress") is not None:
        mode, fraction = "parsed", task["progress"]
    elif expected and elapsed <= expected:
        mode, fraction = "estimate", elapsed / expected
    elif expected:
        mode, fraction = "over", 1.0
    else:
        mode, fraction = "unknown", None
    quiet = now - task.get("mtime", task["start"])
    return {**task, "elapsed": elapsed, "mode": mode, "fraction": fraction, "est": expected, "quiet": quiet}


def render(task, now, cols):
    elapsed = now - task["start"]
    expected = task["estimate"]
    if task["progress"] is not None:
        mode, fraction, percent, timing = "parsed", task["progress"], f"{task['progress'] * 100:3.0f}%", clock(elapsed)
    elif expected and elapsed <= expected:
        fraction = elapsed / expected
        mode, percent, timing = "estimate", f"~{fraction * 100:.0f}%", f"{clock(elapsed)}/~{clock(expected)}"
    elif expected:
        mode, fraction, percent, timing = "over", 1.0, "", f"{clock(elapsed)} +{clock(elapsed - expected)}"
    else:
        mode, fraction, percent, timing = "unknown", None, "", clock(elapsed)
    tone = TONE[mode]
    width = max(6, min(24, cols // 5))
    gauge = bounce(width, now, tone) if fraction is None else bar(fraction, width, tone)
    label = clip(task["key"], max(12, min(48, cols // 4)))
    stats = " ".join(s for s in (percent, timing) if s)
    spin = SPINNER[int(now) % len(SPINNER)]
    row = " ".join((f"{tone}{spin}{RESET}", label, gauge, stats))
    used = len(ANSI.sub("", row))
    quiet = now - task["mtime"]
    if quiet >= QUIET_AFTER:
        note = f"\x1b[33mquiet {clock(quiet)}{RESET}"
    else:
        note = f"{DIM}{clip(task['last'], cols - used - 2)}{RESET}"
    note_len = len(ANSI.sub("", note))
    return f"{row}  {note}" if note_len and used + 2 + note_len <= cols else row


def jround(x):
    return math.floor(x + 0.5)


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def spin(now):
    return SPINNER[int(now) % len(SPINNER)]


def mss(seconds):
    s = int(max(seconds, 0))
    h, m, x = s // 3600, s % 3600 // 60, s % 60
    return f"{h}:{m:02d}:{x:02d}" if h else f"{m}:{x:02d}"


def hhmm(epoch):
    return time.strftime("%H:%M", time.localtime(epoch))


def pad(text, width):
    return text + " " * max(0, width - len(text))


def lpad(text, width):
    return " " * max(0, width - len(text)) + text


def bounce_pos(width, now, size):
    span = max(width - size, 1)
    step = int(now * 2) % (2 * span)
    return step if step < span else 2 * span - step


def sgr(style):
    codes = []
    for token in style.split():
        if token == "b":
            codes.append("1")
        elif token == "dim":
            codes.append("2")
        elif token[:2] in ("F#", "B#"):
            r, g, b = (int(token[i:i + 2], 16) for i in (2, 4, 6))
            codes.append(f"{38 if token[0] == 'F' else 48};2;{r};{g};{b}")
        elif token[0] == "c":
            n = int(token[1:])
            codes.append(str(30 + n if n < 8 else 82 + n))
    return ";".join(codes)


def paint(spans, cols):
    out, left = [], cols
    for text, style in spans:
        if left <= 0:
            break
        text = text[:left]
        left -= len(text)
        if not text:
            continue
        code = sgr(style)
        out.append(f"\x1b[{code}m{text}{RESET}" if code else text)
    return "".join(out)


def span_width(spans):
    return sum(len(text) for text, _ in spans)


def merge(cells):
    out = []
    for ch, style in cells:
        if out and out[-1][1] == style:
            out[-1] = (out[-1][0] + ch, style)
        else:
            out.append((ch, style))
    return out


def with_note(row, t, cols, quiet_style="c3", quiet_text=None, gap="  "):
    used = span_width(row)
    if t["quiet"] >= QUIET_AFTER:
        text = quiet_text(t) if quiet_text else f"quiet {clock(t['quiet'])}"
        return row + [(gap, ""), (text, quiet_style)] if used + len(gap) + len(text) <= cols else row
    text = clip(t.get("last") or "", cols - used - len(gap))
    return row + [(gap, ""), (text, "dim")] if text and used + len(gap) + len(text) <= cols else row


def eighth_cells(fraction, width, style, track, track_style):
    cells = clamp01(fraction) * width
    full = int(cells)
    partial = int((cells - full) * 8) if full < width else 0
    used = full + (1 if partial else 0)
    return [("█" * full + (EIGHTHS[partial] if partial else ""), style), (track * (width - used), track_style)]


DOT = ((0x01, 0x02, 0x04, 0x40), (0x08, 0x10, 0x20, 0x80))


def braille(pred):
    bits = 0
    for c in (0, 1):
        for r in range(4):
            if pred(c, r):
                bits |= DOT[c][r]
    return chr(0x2800 + bits)


FULL = braille(lambda c, r: True)


def rise_order(c, r):
    return c * 4 + (3 - r)


def gauge_width(cols):
    return max(8, min(30, cols // 5))


def dot_number(t):
    if t["mode"] == "parsed":
        src = t.get("src") or ""
        return (src if src.endswith("%") else f"{t['fraction'] * 100:.1f}%"), "b"
    if t["mode"] == "estimate":
        return f"~{jround(t['fraction'] * 100)}%", ""
    if t["mode"] == "over":
        return f"+{jround((t['elapsed'] / t['est'] - 1) * 100)}%", "b c11"
    return "—", "dim"


def dot_row(t, now, cols, gauge):
    lw = max(12, min(40, cols // 4))
    num, style = dot_number(t)
    timing = clock(t["elapsed"])
    if t["mode"] in ("estimate", "over"):
        timing += "/~" + clock(t["est"])
    if t["mode"] == "parsed" and t.get("ratio"):
        timing = f"{t['ratio'][0]}/{t['ratio'][1]} · " + timing
    row = [(spin(now), "b c11" if t["mode"] == "over" else "c12"), (" " + pad(clip(t["key"], lw), lw) + " ", "")]
    row += gauge + [(" ", ""), (lpad(num, 6), style), ("  " + timing, "")]
    return [paint(with_note(row, t, cols, quiet_style="b c11"), cols)]


def rise_gauge(t, now, w):
    if t["mode"] == "unknown":
        cells = []
        for i in range(w):
            h = max(1, jround(2 + 2 * math.sin((i - now * 4) / 2)))
            cells.append((braille(lambda c, r, h=h: r >= 4 - h), "b c12" if h >= 4 else "c12"))
        return merge(cells)
    if t["mode"] == "over":
        return [(FULL * w, "b c11")]
    est = t["mode"] == "estimate"
    per = 4 if est else 8
    steps = int(clamp01(t["fraction"]) * w * per)
    order = (lambda c, r: c * 2 + (3 - r) if r >= 2 else 99) if est else rise_order
    floor = braille(lambda c, r: r == 3)
    cells = []
    for i in range(w):
        local = min(per, max(0, steps - i * per))
        if local:
            cells.append((braille(lambda c, r, local=local: order(c, r) < local), "c12" if est else "b c12"))
        else:
            cells.append((floor, "c8"))
    return merge(cells)


def matrix_gauge(t, now, w):
    quarter = {jround(q * w) - 1 for q in (0.25, 0.5, 0.75)}
    cells = [(FULL, "dim" if i in quarter else "c8") for i in range(w)]
    if t["mode"] == "unknown":
        head = int(now * 3) % (w + 4) - 1
        trail = (FULL, braille(lambda c, r: r >= 1), braille(lambda c, r: r >= 2), braille(lambda c, r: r >= 3))
        for k, ch in enumerate(trail):
            if 0 <= head - k < w:
                cells[head - k] = (ch, "c12" if k else "b c12")
        return merge(cells)
    if t["mode"] == "over":
        return [(FULL * w, "b c11")]
    est = t["mode"] == "estimate"
    steps = int(clamp01(t["fraction"]) * w * 8)
    for i in range(w):
        local = min(8, max(0, steps - i * 8))
        if not local:
            break
        lit = braille(lambda c, r, local=local: rise_order(c, r) < local and (not est or (c + r) % 2 == 0))
        cells[i] = (lit, "c12" if est else "b c12")
    return merge(cells)


def rail_gauge(t, now, w):
    cells = [(braille(lambda c, r: r == 2), "c8") for _ in range(w)]
    if t["mode"] == "unknown":
        cells[bounce_pos(w, now, 1)] = (FULL, "b c12")
        return merge(cells)
    if t["mode"] == "over":
        return [(FULL * w, "b c11")]
    est = t["mode"] == "estimate"
    style = "c12" if est else "b c12"
    full, half = divmod(int(clamp01(t["fraction"]) * w * 2), 2)
    for i in range(full):
        cells[i] = (braille(lambda c, r: not est or r in (1, 2)), style)
    if half and full < w:
        cells[full] = (braille(lambda c, r: c == 0 and (not est or r in (1, 2))), style)
    return merge(cells)


def size_curve(t):
    trail = t.get("sizes") or []
    if len(trail) < 2:
        return None

    def at(x):
        if x <= trail[0][0]:
            return trail[0][1]
        for (t0, s0), (t1, s1) in zip(trail, trail[1:]):
            if x <= t1:
                return s0 + (s1 - s0) * (x - t0) / max(t1 - t0, 1e-6)
        return trail[-1][1]
    return at


def graph_gauge(t, now, w):
    mode = t["mode"]
    if mode == "parsed":
        span = t["elapsed"] / max(t["fraction"], 0.02)
    elif mode in ("estimate", "over"):
        span = max(t["est"], t["elapsed"])
    else:
        span = max(t["elapsed"] * 1.25, 30)
    n, curve, rates = w * 2, size_curve(t), []
    for j in range(n):
        t0, t1 = j / n * span, (j + 1) / n * span
        if t0 >= t["elapsed"]:
            rates.append(None)
            continue
        top = min(t1, t["elapsed"])
        rates.append(0.0 if curve is None else max(0.0, (curve(t["start"] + top) - curve(t["start"] + t0)) / max(top - t0, 1e-6)))
    peak = max([r for r in rates if r is not None] or [0]) or 1
    heights = [-1 if r is None else 1 + jround(min(1, r / peak) * 3) for r in rates]
    cells = []
    for i in range(w):
        hs = heights[i * 2:i * 2 + 2]
        if all(h < 0 for h in hs):
            style = "c8"
        elif mode == "over" and i * 2 / n * span >= t["est"]:
            style = "b c11"
        else:
            style = "b c12" if mode == "parsed" else "c12"
        cells.append((braille(lambda c, r, hs=hs: r == 3 if hs[c] < 0 else r >= 4 - hs[c]), style))
    return merge(cells)


def ruler_rows(t, now, cols, palette):
    lw, w, mode = max(12, min(40, cols // 4)), max(10, min(32, cols // 5)), t["mode"]
    ticks = {jround(q * w) - 1 for q in (0.25, 0.5, 0.75)}
    cells = [("┆" if i in ticks else "·", "dim") for i in range(w)]
    fill = {"parsed": "b c12", "estimate": "c12", "over": "b c11", "unknown": "b c12"}[mode]
    cap = ("▏", "dim")
    if t["fraction"] is None:
        p = bounce_pos(w, now, 3)
        for i in range(p, min(p + 3, w)):
            cells[i] = ("▒", fill)
    else:
        c = clamp01(t["fraction"]) * w
        full = int(c)
        part = int((c - full) * 8) if full < w else 0
        for i in range(full):
            cells[i] = ("▓" if mode == "estimate" else "█", fill)
        if part:
            cells[full] = (EIGHTHS[part], fill)
        if mode == "over":
            cap = ("▶", "b c11")
    pct, timing = "", clock(t["elapsed"])
    if mode == "parsed":
        pct = f"{t['fraction'] * 100:.1f}%"
    elif mode == "estimate":
        pct, timing = f"~{jround(t['fraction'] * 100)}%", f"{clock(t['elapsed'])} of ~{clock(t['est'])}"
    elif mode == "over":
        pct, timing = f"+{jround((t['elapsed'] / t['est'] - 1) * 100)}%", f"{clock(t['elapsed'])} (~{clock(t['est'])})"
    row = [(spin(now), "b c11" if mode == "over" else "c12"), (" " + pad(clip(t["key"], lw), lw) + " ", ""), ("▕", "dim")]
    row += merge(cells) + [cap, (" ", ""), (lpad(pct, 6), "b c11" if mode == "over" else ("b" if mode == "parsed" else "")), (" " + timing, "")]
    return [paint(with_note(row, t, cols, quiet_style="b c11"), cols)]


def digits_rows(t, now, cols, palette):
    w, lw, mode = max(12, min(40, cols // 4)), max(12, min(44, cols // 4)), t["mode"]
    num, style = dot_number(t)
    style = "" if mode == "estimate" else style
    if mode in ("parsed", "estimate"):
        full, half = divmod(int(clamp01(t["fraction"]) * w * 2), 2)
        ch = "╍" if mode == "estimate" else "━"
        bar = [(ch * full + ("╸" if half else ""), "c12" if mode == "estimate" else "b c12"), ("━" * (w - full - half), "c8")]
    elif mode == "over":
        bar = [("━" * w, "b c11")]
    else:
        center = (now * 6) % (w + 10) - 5
        bar = merge([("━", "b c12" if abs(i - center) < 1.5 else "c12" if abs(i - center) < 4 else "c8") for i in range(w)])
    timing = mss(t["elapsed"])
    if mode in ("estimate", "over"):
        timing = f"{mss(t['elapsed'])} / ~{mss(t['est'])}"
    if mode == "parsed" and t.get("ratio"):
        timing = f"{t['ratio'][0]}/{t['ratio'][1]}  " + timing
    row = [(spin(now), "b c11" if mode == "over" else "c12"), (" ", ""), (lpad(num, 6), style), ("  ", "")]
    row += bar + [("  " + pad(clip(t["key"], lw), lw) + "  ", ""), (timing, "")]
    return [paint(with_note(row, t, cols, quiet_style="b c11", quiet_text=lambda x: "quiet " + mss(x["quiet"])), cols)]


def segments_rows(t, now, cols, palette):
    lw, n, mode = max(12, min(40, cols // 4)), 20 if cols >= 90 else 10, t["mode"]
    lit = -1 if t["fraction"] is None else int(clamp01(t["fraction"]) * n)
    march = int(now * 2) % n
    cells = []
    for i in range(n):
        if i and i % 5 == 0:
            cells.append((" ", ""))
        if mode == "unknown":
            cells.append(("■", "b c12") if i == march else ("□", "c8"))
        elif mode == "over":
            cells.append(("■", "b c11"))
        elif i < lit:
            cells.append(("▪", "c12") if mode == "estimate" else ("■", "b c12"))
        else:
            cells.append(("□", "c8"))
    if mode == "over":
        spill = min(5, math.ceil((t["elapsed"] / t["est"] - 1) * n))
        if spill > 0:
            cells += [(" ", ""), ("▸" * spill, "b c11")]
    pct, timing = "", clock(t["elapsed"])
    if mode == "parsed":
        pct = f"{jround(t['fraction'] * 100)}%"
    elif mode == "estimate":
        pct, timing = f"~{jround(t['fraction'] * 100)}%", timing + "/~" + clock(t["est"])
    elif mode == "over":
        pct, timing = f"+{jround((t['elapsed'] / t['est'] - 1) * 100)}%", timing + "/~" + clock(t["est"])
    row = [(spin(now), "b c11" if mode == "over" else "c12"), (" " + pad(clip(t["key"], lw), lw) + " ", "")]
    row += merge(cells) + [(" " + lpad(pct, 5), "b" if mode == "parsed" else "b c11" if mode == "over" else ""), (" " + timing, "")]
    return [paint(with_note(row, t, cols, quiet_style="b c11"), cols)]


def countdown_rows(t, now, cols, palette):
    lw, w, mode = max(12, min(36, cols // 4)), max(10, min(24, cols // 6)), t["mode"]
    remain = None
    if mode == "estimate":
        remain = t["est"] - t["elapsed"]
    elif mode == "parsed" and t["fraction"] >= 0.03 and t["elapsed"] >= 5:
        remain = t["elapsed"] * (1 - t["fraction"]) / t["fraction"]
    hero_style = "b"
    if remain is not None:
        hero = ("≈" if mode == "parsed" else "~") + f"{clock(remain)} left · ends {hhmm(now + remain)}"
    elif mode == "parsed":
        hero = "measuring rate…"
    elif mode == "over":
        hero, hero_style = f"overdue {clock(t['elapsed'] - t['est'])} · usually {clock(t['est'])}", "b c11"
    else:
        hero, hero_style = f"running {clock(t['elapsed'])} · no estimate yet", ""
    if mode == "unknown":
        bar = [("┄" * w, "c8")]
    elif mode == "over":
        bar = [("─" * w, "c11")]
    else:
        keep = jround((1 - clamp01(t["fraction"])) * w)
        bar = [("─" * (w - keep), "c8"), ("━" * keep, "b c12")]
    pct = f"{jround(t['fraction'] * 100)}%" if mode == "parsed" else f"~{jround(t['fraction'] * 100)}%" if mode == "estimate" else ""
    row = [(spin(now), "b c11" if "c11" in hero_style else "c12"), (" " + pad(clip(t["key"], lw), lw) + "  ", ""), (pad(hero, 32), hero_style), (" ", "")]
    row += bar + [(" " + lpad(pct, 4), "dim")]
    return [paint(with_note(row, t, cols, quiet_style="b c11"), cols)]


def history_rows(t, now, cols, palette):
    lw, w, mode = max(12, min(36, cols // 4)), max(16, min(36, cols // 4)), t["mode"]
    xs = t.get("samples") or []
    med = median(xs) if xs else None
    lo, hi = (min(xs), max(xs)) if xs else (None, None)
    if mode == "parsed":
        cells = [("─", "c8") for _ in range(w)]
        c = clamp01(t["fraction"]) * w
        full = int(c)
        part = int((c - full) * 8) if full < w else 0
        for i in range(full):
            cells[i] = ("█", "b c12")
        if part:
            cells[full] = (EIGHTHS[part], "b c12")
        pace = min(1, t["elapsed"] / med) if med else None
        if pace is not None:
            cells[min(w - 1, jround(pace * w))] = ("┃", "b c11")
        src = t.get("src") or ""
        summary = (src if src.endswith("%") else f"{t['fraction'] * 100:.1f}%")
        summary += f" · usual pace {jround(pace * 100)}% " + ("▲ ahead" if t["fraction"] >= pace else "▼ behind") if pace is not None else " · first run, no pace yet"
    else:
        span = max(hi or 0, t["elapsed"], 30 if mode == "unknown" else 0) * (1.25 if mode == "unknown" else 1.15)
        cells = []
        for i in range(w):
            ti = (i + 0.5) / w * span
            inside = bool(xs) and lo <= ti <= hi
            cells.append(("─", "c8") if inside else ("·", "dim"))
        fill = "b c11" if mode == "over" else "b c12"
        c = min(t["elapsed"] / span, 1) * w
        full = int(c)
        part = int((c - full) * 8) if full < w else 0
        for i in range(full):
            cells[i] = ("█", fill)
        if part:
            cells[full] = (EIGHTHS[part], fill)
        if med:
            cells[min(w - 1, int(med / span * w))] = ("┃", "b c11")
        if mode == "estimate":
            summary = f"{clock(t['elapsed'])} · usual {clock(med)} ({clock(lo)}–{clock(hi)}, {len(xs)} run{'s' if len(xs) > 1 else ''})"
        elif mode == "over":
            summary = f"{clock(t['elapsed'])} · {clock(t['elapsed'] - med)} past usual" + (" · longest yet" if t["elapsed"] > hi else "") if med else f"{clock(t['elapsed'])} · over"
        else:
            summary = f"{clock(t['elapsed'])} · first run, recording"
    row = [(spin(now), "b c11" if mode == "over" else "c12"), (" " + pad(clip(t["key"], lw), lw) + " ", ""), ("▕", "dim")]
    row += merge(cells) + [("▏", "dim"), (" " + summary, "c11" if mode == "over" else "")]
    return [paint(with_note(row, t, cols, quiet_style="b c11"), cols)]


def rgb(code):
    return [int(code[i:i + 2], 16) for i in (1, 3, 5)]


def mix(a, b, t):
    return [x + (y - x) * t for x, y in zip(a, b)]


def q8(m):
    return jround(min(max(m, 0), 1) * 8) / 8


def wave(ms, period, offset=0.0):
    return 0.5 + 0.5 * math.sin((ms / period + offset) * math.pi * 2)


def q17(c):
    return [max(0, min(255, jround(v / 17) * 17)) for v in c]


def hexof(c):
    return "#" + "".join(f"{v:02x}" for v in q17(c))


def luminance(c):
    lin = [v / 255 / 12.92 if v / 255 <= 0.03928 else ((v / 255 + 0.055) / 1.055) ** 2.4 for v in q17(c)]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def ink_on(c):
    white = [255, 255, 255]
    ratio = (max(luminance(white), luminance(c)) + 0.05) / (min(luminance(white), luminance(c)) + 0.05)
    return white if ratio >= 4.5 else [14, 20, 22]


def hash3(x, y, seed):
    h = (x * 374761393 + y * 668265263 + seed * 982451653) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h ^= h >> 16
    return h / 4294967296


BRAILLE_BITS = ((0x01, 0x08), (0x02, 0x10), (0x04, 0x20), (0x40, 0x80))
DEFAULT_PALETTE = {"run": rgb("#8b7cf6"), "done": rgb("#9bd8a8"), "over": rgb("#e6c46a"), "back": rgb("#000000")}


def load_palette(path):
    palette = dict(DEFAULT_PALETTE)
    if not path:
        return palette
    try:
        with open(os.path.expanduser(path)) as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and HEX.fullmatch(parts[1]):
                    if parts[0] == "color12":
                        palette["run"] = rgb(parts[1])
                    elif parts[0] == "background":
                        palette["back"] = rgb(parts[1])
    except OSError:
        pass
    return palette


def dot_field(width, spec, ms, back):
    track = mix(back, [128, 128, 128], 0.18)
    acc, done = spec["acc"], spec.get("done", False)
    light, grey = mix(acc, [255, 255, 255], 0.35), [120, 118, 128]
    fill = mix(track, acc, 0.3 if done else 0.17)
    lo, fx = spec.get("from", 0), spec["to"]
    span = max(1, fx - lo)
    cells = [[" ", None, fill if lo <= x + 0.5 < fx else track] for x in range(width)]
    twinkle = (3200, 3800, 4400, 3500) if done else (2200, 2800, 1900, 3300)
    delay, depth = (0, 700, 1300, 400), 0.2 if done else 0.55
    for col in range(max(0, math.floor(lo)), min(width, math.ceil(fx))):
        u = min(1, max(0, (col + 0.5 - lo) / span))
        dense = 0.8 if done else (0.22 + 0.78 * u ** 1.5) * (0.6 if spec.get("sparse") else 1)
        bits = 0
        for r in range(4):
            for c in range(2):
                sx = col * 2 + c
                if sx / 2 >= fx or sx / 2 < lo or hash3(sx, r, 1) > dense * 0.6:
                    continue
                bits |= BRAILLE_BITS[r][c]
        if not bits:
            continue
        group = math.floor(hash3(col, 0, 2) * 4)
        blink = 1 - depth * wave(ms + delay[group], twinkle[group], 0.25)
        bucket = 1 if done else q8(min(1, u ** 0.9 * 1.1))
        cells[col] = [chr(0x2800 + bits), mix(fill, mix(grey, light, bucket), q8((0.35 + 0.65 * dense) * blink)), fill]
    if spec.get("marks"):
        for m in (0.25, 0.5, 0.75):
            x = jround(m * width)
            if 0 < x < width - 1:
                cells[x] = ["│", mix(light, [255, 255, 255], 0.5) if x < fx - 0.5 else mix(track, [255, 255, 255], 0.3), cells[x][2]]
    if spec.get("pill"):
        text, color = spec["pill"]
        kw = len(text) + 2
        kx = jround(max(0, min(width - kw, fx - kw / 2)))
        ink = ink_on(color)
        for x in range(kx, min(width, kx + kw)):
            cells[x] = [" ", None, color]
        for i, ch in enumerate(text):
            if kx + 1 + i < width:
                cells[kx + 1 + i] = [ch, ink, color]
    return merge([(ch, ("F" + hexof(fg) + " " if fg else "") + "B" + hexof(bg)) for ch, fg, bg in cells])


def field_spec(t, width, ms, palette):
    track = mix(palette["back"], [128, 128, 128], 0.18)
    roomy, mode = width >= 46, t["mode"]
    if mode == "done":
        return {"to": width, "acc": palette["done"], "done": True, "marks": True, "pill": ("✓ " + clock(t["elapsed"]), palette["done"]), "right": "100%", "style": "F" + hexof(palette["done"])}
    if mode == "over":
        pill = "+" + clock(t["elapsed"] - t["est"]) + (" past ~" + clock(t["est"]) if roomy else "")
        return {"to": width, "acc": palette["over"], "marks": True, "pill": (pill, palette["over"]), "right": f"+{jround((t['elapsed'] / t['est'] - 1) * 100)}%", "style": "b F" + hexof(palette["over"])}
    if mode == "unknown":
        span = width * 0.32
        head = span + (width - span) * (0.5 - 0.5 * math.cos(ms / 2400 * math.pi))
        return {"from": head - span, "to": head, "acc": palette["run"], "pill": (clock(t["elapsed"]), mix(palette["run"], track, 0.35)), "right": "—", "style": "dim"}
    to = clamp01(t["fraction"]) * width
    if mode == "estimate":
        pill = f"{clock(t['elapsed'])} / ~{clock(t['est'])}" if roomy else "~" + clock(t["est"] - t["elapsed"])
        return {"to": to, "acc": palette["run"], "sparse": True, "marks": True, "pill": (pill, mix(palette["run"], track, 0.45)), "right": f"~{jround(t['fraction'] * 100)}%", "style": ""}
    src = t.get("src") or ""
    pill = f"{t['ratio'][0]}/{t['ratio'][1]}" if t.get("ratio") else clock(t["elapsed"])
    return {"to": to, "acc": palette["run"], "marks": True, "pill": (pill, palette["run"]), "right": src if src.endswith("%") else f"{t['fraction'] * 100:.1f}%", "style": "b"}


def field_rows(t, now, cols, palette):
    ms = math.floor(now) * 1000
    lw = max(12, min(34, int(cols * 0.22)))
    width = max(14, cols - lw - 11)
    spec, mode = field_spec(t, width, ms, palette), t["mode"]
    dot = palette["done"] if mode == "done" else palette["over"] if mode == "over" else mix(palette["run"], [255, 255, 255], 0.3 * wave(ms, 1100))
    bar = [("✓ " if mode == "done" else "● ", "F" + hexof(dot)), (pad(clip(t["key"], lw), lw) + "  ", "")]
    bar += dot_field(width, spec, ms, palette["back"]) + [(" " + lpad(spec["right"], 6), spec["style"])]
    indent = " " * (lw + 4)
    if mode != "done" and t["quiet"] >= QUIET_AFTER:
        strip = [(indent + "⎿ ", ""), ("quiet " + clock(t["quiet"]), "F" + hexof(palette["over"]))]
    else:
        strip = [(indent + "⎿ ", "dim"), (clip("finished" if mode == "done" else (t.get("last") or ""), width), "dim")]
    return [paint(bar, cols), paint(strip, cols)]


def plain_overflow(hidden, now, cols):
    return [f"{DIM}  +{len(hidden)} more running{RESET}"]


def names_overflow(hidden, now, cols):
    return [paint([(f"  +{len(hidden)} more · " + ", ".join(h["key"] for h in hidden), "dim")], cols)]


def countdown_overflow(hidden, now, cols):
    ends = sorted(h["start"] + h["estimate"] for h in hidden if h.get("estimate") and now - h["start"] <= h["estimate"])
    tail = f" · next ends ~{hhmm(ends[0])}" if ends else " · " + ", ".join(h["key"] for h in hidden)
    return [paint([(f"  +{len(hidden)} more" + tail, "dim")], cols)]


def gauge_style(gauge):
    return lambda t, now, cols, palette: dot_row(t, now, cols, gauge(t, now, gauge_width(cols)))


STYLES = {
    "rise": (gauge_style(rise_gauge), names_overflow),
    "dots": (gauge_style(matrix_gauge), names_overflow),
    "rail": (gauge_style(rail_gauge), names_overflow),
    "graph": (gauge_style(graph_gauge), names_overflow),
    "field": (field_rows, names_overflow),
    "today": (lambda t, now, cols, palette: [render(t, now, cols)], plain_overflow),
    "ruler": (ruler_rows, plain_overflow),
    "digits": (digits_rows, names_overflow),
    "segments": (segments_rows, names_overflow),
    "countdown": (countdown_rows, countdown_overflow),
    "history": (history_rows, names_overflow),
}


def visible_tasks(tasks, now):
    return sorted((t for t in tasks if now - t["start"] >= MIN_ELAPSED), key=lambda t: t["start"])


def rows(tasks, now, cols, hidden, style, palette=None):
    draw, overflow = STYLES[style]
    out = [line for t in tasks for line in draw(facts(t, now), now, cols, palette or DEFAULT_PALETTE)]
    if hidden:
        out.extend(overflow(hidden, now, cols))
    return out


def progress_rows(session, state_path, history_path, cols, max_rows, style=DEFAULT_STYLE, palette=None):
    now = time.time()
    tasks = running_tasks(session)
    finished = track(state_path, history_path, tasks, now, sizes=style == "graph")
    visible = visible_tasks(tasks, now)
    if style == "field":
        lingering = [{"key": d["key"], "family": family(d["key"]), "start": d["start"], "duration": d["duration"], "done": True} for d in finished]
        visible = sorted(visible + lingering, key=lambda t: t["start"])
    if not visible:
        return []
    exact, families = load_history(history_path)
    shown = [
        t if t.get("done") else enrich(t, output_lines(t["out"]), file_mtime(t["out"], t["start"]), exact, families)
        for t in visible[:max_rows]
    ]
    hidden = [{**t, "estimate": estimate(t, exact, families)} for t in visible[max_rows:]]
    return rows(shown, now, cols, hidden, style, palette)


def columns():
    try:
        fd = os.open("/dev/tty", os.O_RDONLY)
        try:
            cols = os.get_terminal_size(fd).columns
        finally:
            os.close(fd)
    except OSError:
        cols = int(os.environ.get("COLUMNS") or 124)
    return max(cols - 4, 20)


def version_key(path):
    return [int(p) if p.isdigit() else p for p in re.findall(r"\d+|\D+", path)]


def hud_command(wrap):
    if wrap is not None:
        return wrap or None
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    entries = sorted(glob.glob(os.path.join(base, "plugins/cache/*/claude-hud/*/dist/index.js")), key=version_key)
    node = shutil.which("node")
    return [node, entries[-1]] if entries and node else None


def hud_output(command, raw, data, cols, cache_path):
    try:
        st = os.stat(data.get("transcript_path") or "")
        stamp = f"{st.st_mtime_ns}:{st.st_size}"
    except OSError:
        stamp = ""
    stable = json.dumps({k: v for k, v in data.items() if k != "cost"}, sort_keys=True)
    key = hashlib.sha1(f"{stable}|{stamp}|{cols}|{command}".encode()).hexdigest()
    cached = read_json(cache_path)
    if cached.get("key") == key and time.time() - cached.get("t", 0) < HUD_MAX_AGE:
        return cached.get("out", "")
    import subprocess
    try:
        result = subprocess.run(
            command,
            shell=isinstance(command, str),
            input=raw,
            capture_output=True,
            text=True,
            timeout=HUD_TIMEOUT,
            env={**os.environ, "COLUMNS": str(cols)},
        )
        out = result.stdout.rstrip("\n")
    except (OSError, subprocess.TimeoutExpired):
        return cached.get("out", "")
    write_atomic(cache_path, json.dumps({"key": key, "t": time.time(), "out": out}))
    return out


USAGE = (
    "usage: statusline.py [--wrap CMD] [--max-rows N] [--style NAME] [--palette KITTY_COLORS]\n"
    f"  N >= 1, default {DEFAULT_ROWS}; NAME is one of {', '.join(STYLES)}, default {DEFAULT_STYLE}"
)


def options(argv):
    wrap, max_rows, style, palette = None, DEFAULT_ROWS, DEFAULT_STYLE, None
    pairs = []
    for arg in argv:
        if pairs and pairs[-1][1] is None:
            pairs[-1][1] = arg
        elif "=" in arg:
            pairs.append(arg.split("=", 1))
        else:
            pairs.append([arg, None])
    for flag, value in pairs:
        if flag == "--wrap":
            wrap = value or ""
        elif flag == "--max-rows" and value and value.isdigit() and int(value) > 0:
            max_rows = int(value)
        elif flag == "--style" and value in STYLES:
            style = value
        elif flag == "--palette" and value:
            palette = value
        else:
            sys.exit(USAGE)
    return wrap, max_rows, style, palette


def main():
    wrap, max_rows, style, palette_path = options(sys.argv[1:])
    palette = load_palette(palette_path) if style == "field" else None
    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except ValueError:
        data = {}
    session = str(data.get("session_id") or "default")
    slug = hashlib.sha1(session.encode()).hexdigest()[:16]
    runtime = state_dir("XDG_RUNTIME_DIR", f"/tmp/progress-hud-{os.getuid()}")
    cols = columns()
    lines = []
    command = hud_command(wrap)
    if command:
        hud = hud_output(command, raw, data, cols, os.path.join(runtime, f"hud-{slug}.json"))
        if hud:
            lines.append(hud)
    try:
        history = os.path.join(state_dir("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "history.jsonl")
        lines.extend(progress_rows(session, os.path.join(runtime, f"state-{slug}.json"), history, cols, max_rows, style, palette))
    except Exception:
        import traceback
        traceback.print_exc()
    sys.stdout.write("\n".join(lines))

