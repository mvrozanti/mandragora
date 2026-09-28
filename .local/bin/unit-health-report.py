import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

SYSTEM_DIR = Path(os.environ["UNIT_HEALTH_SYSTEM_DIR"])
STATE_HOME = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
USER_DIR = STATE_HOME / "unit-health"
SEEN = USER_DIR / "seen.json"
REMOTE = os.environ.get("UNIT_HEALTH_REMOTE", "opc@100.84.78.83")
REMOTE_DIR = os.environ.get("UNIT_HEALTH_REMOTE_DIR", "/home/opc/watch/health")
SLACK = int(os.environ.get("UNIT_HEALTH_SLACK", "3600"))
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15"]

UNITS = {
    "us": 1e-6, "ms": 1e-3, "s": 1, "sec": 1, "m": 60, "min": 60, "h": 3600, "hr": 3600,
    "d": 86400, "day": 86400, "w": 604800, "week": 604800, "M": 2629800, "month": 2629800,
    "y": 31557600, "year": 31557600,
}
SPAN_RE = re.compile(r"(\d+(?:\.\d+)?)\s*([a-zA-Z]+)")
REPEAT_RE = re.compile(r"On(?:UnitActive|UnitInactive)USec=([^;]+?)\s*;")
CALENDAR_RE = re.compile(r"OnCalendar=(.+?)\s*;")
UTC_RE = re.compile(r"\(in UTC\): \w+ (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) UTC")


def systemctl(scope, *args):
    return subprocess.run(["systemctl", scope, *args], capture_output=True, text=True, check=True).stdout


def show(scope, unit, *props):
    out = {}
    args = [a for p in props for a in ("-p", p)]
    for line in systemctl(scope, "show", unit, *args).splitlines():
        key, _, value = line.partition("=")
        out.setdefault(key, []).append(value)
    return out


def timespan(text):
    total = 0.0
    for num, unit in SPAN_RE.findall(text):
        if unit not in UNITS:
            return None
        total += float(num) * UNITS[unit]
    return total or None


def calendar_period(spec):
    try:
        out = subprocess.run(
            ["systemd-analyze", "calendar", "--iterations=8", spec],
            capture_output=True, text=True, check=True,
        ).stdout
    except subprocess.CalledProcessError:
        return None
    stamps = [datetime.strptime(s, "%Y-%m-%d %H:%M:%S").timestamp() for s in UTC_RE.findall(out)]
    gaps = [b - a for a, b in zip(stamps, stamps[1:]) if b > a]
    return max(gaps) if gaps else None


def period(scope, timer):
    props = show(scope, timer, "TimersMonotonic", "TimersCalendar")
    found = []
    for entry in props.get("TimersMonotonic", []):
        found += [timespan(m) for m in REPEAT_RE.findall(entry)]
    for entry in props.get("TimersCalendar", []):
        found += [calendar_period(m) for m in CALENDAR_RE.findall(entry)]
    found = [f for f in found if f]
    return min(found) if found else None


def iso(ts):
    if ts is None:
        return None
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def mtime(path):
    try:
        return path.stat().st_mtime
    except FileNotFoundError:
        return None


def failing(path):
    try:
        since, count, *_ = path.read_text().split()
        return int(since), int(count)
    except (FileNotFoundError, ValueError):
        return None


def load_seen():
    try:
        return json.loads(SEEN.read_text())
    except (FileNotFoundError, ValueError):
        return {}


def collect(now, seen):
    units = []
    for scope, name, state_dir in (("--system", "system", SYSTEM_DIR), ("--user", "user", USER_DIR)):
        listed = set()
        for t in json.loads(systemctl(scope, "list-timers", "--all", "-o", "json")):
            unit, timer = t.get("activates") or "", t.get("unit") or ""
            if not unit.endswith(".service"):
                continue
            listed.add(unit)
            key = f"{name}:{unit}"
            seen.setdefault(key, now)
            active = show(scope, timer, "ActiveState").get("ActiveState", [""])[0] == "active"
            every = period(scope, timer)
            last_ok = mtime(state_dir / f"{unit}.ok")
            fail = failing(state_dir / f"{unit}.failing")
            ref = last_ok if last_ok is not None else seen[key]
            due = ref + 2 * every + SLACK if every else None
            if fail:
                status = "failing"
            elif not active:
                status = "inactive"
            elif due is not None and now > due:
                status = "stale"
            else:
                status = "ok"
            units.append({
                "unit": unit,
                "timer": timer,
                "scope": name,
                "status": status,
                "period": int(every) if every else None,
                "last_ok": iso(last_ok),
                "watched_since": iso(seen[key]),
                "due_by": iso(due),
                "failing_since": iso(fail[0]) if fail else None,
                "failures": fail[1] if fail else 0,
            })
        for path in sorted(state_dir.glob("*.failing")) if state_dir.is_dir() else []:
            unit = path.name[: -len(".failing")]
            fail = failing(path)
            if unit in listed or not fail:
                continue
            units.append({
                "unit": unit,
                "timer": None,
                "scope": name,
                "status": "failing",
                "period": None,
                "last_ok": iso(mtime(state_dir / f"{unit}.ok")),
                "watched_since": None,
                "due_by": None,
                "failing_since": iso(fail[0]),
                "failures": fail[1],
            })
    return units


def publish(report_path, host):
    target = f"{REMOTE}:{REMOTE_DIR}/health-{host}.json"
    for attempt in range(3):
        result = subprocess.run(["rsync", "-a", "-e", " ".join(SSH), str(report_path), target])
        if result.returncode == 0:
            return
        time.sleep(20 * (attempt + 1))
    sys.exit(f"could not publish to {target}")


def main():
    USER_DIR.mkdir(parents=True, exist_ok=True)
    now = time.time()
    host = socket.gethostname()
    seen = load_seen()
    units = collect(now, seen)
    SEEN.write_text(json.dumps(seen, sort_keys=True))
    report = {"schema": 1, "host": host, "generated": iso(now), "units": units}
    with tempfile.NamedTemporaryFile("w", dir=USER_DIR, delete=False, suffix=".json") as f:
        json.dump(report, f, indent=1)
    path = Path(f.name)
    path.chmod(0o644)
    final = USER_DIR / "report.json"
    path.replace(final)
    counts = {}
    for u in units:
        counts[u["status"]] = counts.get(u["status"], 0) + 1
    print(f"{len(units)} timer-driven units: {counts}")
    for u in units:
        if u["status"] in ("stale", "failing"):
            print(f"  {u['status']}: {u['scope']} {u['unit']} last_ok={u['last_ok']} due_by={u['due_by']}")
    if os.environ.get("UNIT_HEALTH_NO_PUBLISH"):
        return
    publish(final, host)


if __name__ == "__main__":
    main()
