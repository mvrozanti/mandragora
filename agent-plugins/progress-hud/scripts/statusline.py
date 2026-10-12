#!/usr/bin/env python3
import glob
import hashlib
import json
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

SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
EIGHTHS = " ▏▎▍▌▋▊▉"
RESET = "\x1b[0m"
DIM = "\x1b[2m"
TONE = {"parsed": "\x1b[32m", "estimate": "\x1b[36m", "over": "\x1b[33m", "unknown": "\x1b[35m"}

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


def runtime_dir():
    return state_dir("XDG_RUNTIME_DIR", f"/tmp/progress-hud-{os.getuid()}")


def history_file():
    return os.path.join(state_dir("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "history.jsonl")


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
    text = " ".join(command.split())
    while (m := CD_PREFIX.match(text)):
        text = text[m.end():]
    words = text.split(" ")
    while words:
        if ASSIGNMENT.fullmatch(words[0]) or words[0] in WRAPPERS:
            words.pop(0)
        elif words[0] == "timeout" and len(words) > 1:
            words.pop(0)
            while words and (words[0].startswith("-") or DURATION.fullmatch(words[0])):
                words.pop(0)
        else:
            break
    return (" ".join(words) or text)[:200]


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


def parse_progress(lines):
    for line in reversed(lines):
        percents = [float(m.group(1)) for m in PERCENT.finditer(line) if float(m.group(1)) <= 100]
        if percents:
            return percents[-1] / 100
        ratios = []
        for m in FRACTION.finditer(line):
            done, total = (int(m.group(1)), int(m.group(2))) if m.group(1) else (int(m.group(3)), int(m.group(4)))
            if total >= 2 and done <= total:
                ratios.append(done / total)
        if ratios:
            return ratios[-1]
    return None


def candidates(owner):
    if owner is None:
        return [name for name in os.listdir("/proc") if name.isdigit()]
    pids = []
    for tid in os.listdir(f"/proc/{owner}/task"):
        try:
            with open(f"/proc/{owner}/task/{tid}/children") as f:
                pids.extend(f.read().split())
        except OSError:
            continue
    return pids


def running_tasks(session):
    owner = claude_ancestor()
    ticks = os.sysconf("SC_CLK_TCK")
    btime = boot_time()
    found = {}
    for name in candidates(owner):
        try:
            target = os.readlink(f"/proc/{name}/fd/1")
        except OSError:
            continue
        if not TASK_OUTPUT.search(target):
            continue
        if owner is None and f"/{session}/" not in target:
            continue
        try:
            _, ppid, start = proc_stat(name)
            argv = proc_argv(name)
        except OSError:
            continue
        if owner is not None and ppid != owner:
            continue
        path = target.removesuffix(" (deleted)")
        began = btime + start / ticks
        if path in found and found[path]["start"] <= began:
            continue
        key = normalize(extract_command(argv))
        found[path] = {"pid": name, "out": path, "start": began, "key": key, "family": family(key)}
    return list(found.values())


def load_history():
    exact, families = {}, {}
    try:
        with open(history_file()) as f:
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
    ordered = sorted(samples[-HISTORY_SAMPLES:])
    mid = len(ordered) // 2
    return ordered[mid] if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2


def estimate(task, exact, families):
    if exact.get(task["key"]):
        return median(exact[task["key"]])
    samples = families.get(task["family"], [])[-HISTORY_SAMPLES:]
    if len(samples) >= 2 and max(samples) <= FAMILY_SPREAD * min(samples):
        return median(samples)
    return None


def append_history(entries):
    path = history_file()
    with open(path, "a") as f:
        f.write("".join(json.dumps(e) + "\n" for e in entries))
    if os.path.getsize(path) > HISTORY_MAX_BYTES:
        with open(path) as f:
            kept = f.readlines()[-HISTORY_KEEP:]
        write_atomic(path, "".join(kept))


def track(session, tasks, now):
    path = os.path.join(runtime_dir(), f"state-{hashlib.sha1(session.encode()).hexdigest()[:16]}.json")
    previous = read_json(path)
    alive = {t["pid"]: t for t in tasks}
    finished = []
    for pid, seen in previous.items():
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
    if finished:
        append_history(finished)
    state = {t["pid"]: {"s": t["start"], "l": now, "o": t["out"], "k": t["key"], "f": t["family"]} for t in tasks}
    if state or previous:
        write_atomic(path, json.dumps(state))


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
    used = 2 + len(label) + 1 + width + 1 + len(stats)
    quiet = now - task["mtime"]
    if quiet >= QUIET_AFTER:
        note = f"\x1b[33mquiet {clock(quiet)}{RESET}"
        note_len = len(f"quiet {clock(quiet)}")
    else:
        text = clip(task["last"], cols - used - 2)
        note, note_len = f"{DIM}{text}{RESET}", len(text)
    tail = f"  {note}" if note_len and used + 2 + note_len <= cols else ""
    spin = SPINNER[int(now) % len(SPINNER)]
    return f"{tone}{spin}{RESET} {label} {gauge} {stats}{tail}"


def progress_rows(session, cols, max_rows):
    now = time.time()
    tasks = running_tasks(session)
    track(session, tasks, now)
    visible = sorted((t for t in tasks if now - t["start"] >= MIN_ELAPSED), key=lambda t: -t["start"])
    if not visible:
        return []
    exact, families = load_history()
    rows = []
    for task in visible[:max_rows]:
        lines = output_lines(task["out"])
        try:
            task["mtime"] = os.stat(task["out"]).st_mtime
        except OSError:
            task["mtime"] = task["start"]
        task["mtime"] = max(task["mtime"], task["start"])
        task["last"] = lines[-1] if lines else ""
        task["progress"] = parse_progress(lines)
        task["estimate"] = estimate(task, exact, families)
        rows.append(render(task, now, cols))
    if len(visible) > max_rows:
        rows.append(f"{DIM}  +{len(visible) - max_rows} more running{RESET}")
    return rows


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


def hud_output(command, raw, data, cols, session):
    try:
        st = os.stat(data.get("transcript_path") or "")
        stamp = f"{st.st_mtime_ns}:{st.st_size}"
    except OSError:
        stamp = ""
    stable = json.dumps({k: v for k, v in data.items() if k != "cost"}, sort_keys=True)
    key = hashlib.sha1(f"{stable}|{stamp}|{cols}|{command}".encode()).hexdigest()
    cache = os.path.join(runtime_dir(), f"hud-{hashlib.sha1(session.encode()).hexdigest()[:16]}.json")
    cached = read_json(cache)
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
    write_atomic(cache, json.dumps({"key": key, "t": time.time(), "out": out}))
    return out


def options(argv):
    wrap, max_rows = None, 3
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
        elif flag == "--max-rows" and value and value.isdigit():
            max_rows = int(value)
        else:
            sys.exit("usage: statusline.py [--wrap CMD] [--max-rows N]")
    return wrap, max_rows


def main():
    wrap, max_rows = options(sys.argv[1:])
    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except ValueError:
        data = {}
    session = str(data.get("session_id") or "default")
    cols = columns()
    lines = []
    command = hud_command(wrap)
    if command:
        hud = hud_output(command, raw, data, cols, session)
        if hud:
            lines.append(hud)
    try:
        lines.extend(progress_rows(session, cols, max_rows))
    except Exception:
        pass
    sys.stdout.write("\n".join(lines))


if __name__ == "__main__":
    main()
