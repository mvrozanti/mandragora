import os
import socket
import socketserver
import subprocess
import threading
import time
from datetime import date, datetime, timedelta
from pathlib import Path

BIND = os.environ.get("AGENDA_BIND", "0.0.0.0")
PORT = int(os.environ.get("AGENDA_PORT", "6616"))
TTL = int(os.environ.get("AGENDA_TTL", "60"))
DAYS = int(os.environ.get("AGENDA_DAYS", "14"))
LIMIT = int(os.environ.get("AGENDA_LIMIT", "60"))
KHAL = os.environ.get("AGENDA_KHAL", "khal")
KHAL_TIMEOUT = int(os.environ.get("AGENDA_KHAL_TIMEOUT", "30"))
DATE_FORMAT = os.environ.get("AGENDA_DATE_FORMAT", "%d/%m/%Y")
HOME = Path(os.environ.get("HOME", "/home/m"))
SYNC_STAMP = Path(os.environ.get(
    "AGENDA_SYNC_STAMP", str(HOME / ".local/state/vdirsyncer/last-sync")))

SEP = "\x1f"
DAY_FORMAT = "DAY" + SEP + "{date}"
EVENT_FORMAT = SEP.join(
    ["E", "{start-time}", "{end-time}", "{calendar}", "{title}", "{location}"])

_lock = threading.Lock()
_cache = {"at": 0.0, "days": [], "errors": []}


def day_label(day, today):
    if day == today:
        return "today"
    if day == today + timedelta(days=1):
        return "tomorrow"
    return day.strftime("%a %d %b").lower()


def clean(value):
    return " ".join(value.replace("\t", " ").split())


def read_agenda():
    result = subprocess.run(
        [KHAL, "list", "today", "%dd" % DAYS,
         "--day-format", DAY_FORMAT, "--format", EVENT_FORMAT],
        capture_output=True, text=True, timeout=KHAL_TIMEOUT)
    if result.returncode != 0:
        message = (result.stderr or result.stdout).strip().splitlines()
        raise RuntimeError(message[-1][:80] if message else "khal failed")

    today = date.today()
    days = []
    for line in result.stdout.splitlines():
        fields = line.split(SEP)
        if fields[0] == "DAY" and len(fields) == 2:
            try:
                day = datetime.strptime(fields[1].strip(), DATE_FORMAT).date()
            except ValueError:
                continue
            days.append({"date": day, "label": day_label(day, today), "events": []})
        elif fields[0] == "E" and len(fields) == 6 and days:
            days[-1]["events"].append({
                "start": clean(fields[1]),
                "end": clean(fields[2]),
                "calendar": clean(fields[3]),
                "title": clean(fields[4]),
                "location": clean(fields[5]),
            })
    return days


def snapshot(force=False):
    with _lock:
        age = time.time() - _cache["at"]
        if not force and _cache["at"] and age < TTL:
            return _cache["days"], _cache["errors"]
        try:
            days, errors = read_agenda(), []
        except Exception as exc:
            days, errors = _cache["days"], [str(exc)[:80]]
        _cache.update({"at": time.time(), "days": days, "errors": errors})
        return days, errors


def sync_age():
    try:
        return str(max(0, int(time.time() - int(SYNC_STAMP.read_text().strip()))))
    except (OSError, ValueError):
        return "never"


def lines_for(days, errors):
    out = ["SYNC " + sync_age()]
    room = LIMIT
    hidden = 0
    for day in days:
        if room <= 0:
            hidden += len(day["events"])
            continue
        out.append("DAY\t%s\t%s" % (day["date"].isoformat(), day["label"]))
        for event in day["events"]:
            if room <= 0:
                hidden += 1
                continue
            out.append("E\t%s\t%s\t%s\t%s\t%s" % (
                event["start"] or "-", event["end"] or "-",
                event["calendar"] or "-", event["title"] or "-",
                event["location"] or "-"))
            room -= 1
    if hidden:
        out.append("MORE %d" % hidden)
    for err in errors[:3]:
        out.append("ERR " + err)
    return out


class Handler(socketserver.StreamRequestHandler):
    timeout = 120

    def handle(self):
        while True:
            try:
                raw = self.rfile.readline()
            except (socket.timeout, OSError):
                return
            if not raw:
                return
            request = raw.decode("utf8", "replace").strip()
            if not request:
                self.reply("ERR empty request")
                continue
            verb = request.split()[0].upper()
            if verb == "QUIT":
                return
            if verb == "PING":
                self.reply("PONG")
                continue
            if verb in ("NOW", "REFRESH"):
                days, errors = snapshot(force=(verb == "REFRESH"))
                for line in lines_for(days, errors):
                    self.reply(line)
                self.reply("END")
                continue
            self.reply("ERR unknown verb " + verb)

    def reply(self, line):
        self.wfile.write((line + "\n").encode("utf8"))
        self.wfile.flush()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    Server((BIND, PORT), Handler).serve_forever()
