import json
import os
import socket
import socketserver
import threading
import time
import urllib.parse
import urllib.request

BIND = os.environ.get("WEATHER_BIND", "0.0.0.0")
PORT = int(os.environ.get("WEATHER_PORT", "6615"))
TTL = int(os.environ.get("WEATHER_TTL", "900"))
TIMEOUT = int(os.environ.get("WEATHER_HTTP_TIMEOUT", "20"))
KEY_FILE = os.environ.get("WEATHER_KEY_FILE", "/run/secrets/weather/api_key")
CITY_ID = os.environ.get("WEATHER_CITY_ID", "3448439")
UNITS = os.environ.get("WEATHER_UNITS", "metric")
API = "https://api.openweathermap.org/data/2.5"

_lock = threading.Lock()
_cache = {"at": 0.0, "now": None, "days": [], "errors": []}


def _key():
    with open(KEY_FILE, "r") as handle:
        return handle.read().strip()


def _get(path, key):
    query = urllib.parse.urlencode({"id": CITY_ID, "units": UNITS, "appid": key})
    request = urllib.request.Request(API + path + "?" + query,
                                     headers={"User-Agent": "mandragora-weather"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf8"))


def _day_key(stamp, offset):
    return time.strftime("%Y-%m-%d", time.gmtime(stamp + offset))


def _refresh():
    key = _key()
    errors = []
    now = None
    days = []

    try:
        current = _get("/weather", key)
        weather = (current.get("weather") or [{}])[0]
        main = current.get("main") or {}
        wind = current.get("wind") or {}
        now = {
            "place": current.get("name") or "",
            "temp": main.get("temp"),
            "feels": main.get("feels_like"),
            "humidity": main.get("humidity"),
            "wind": wind.get("speed"),
            "desc": (weather.get("description") or "").strip(),
        }
    except Exception as exc:
        errors.append("current: " + str(exc)[:50])

    try:
        forecast = _get("/forecast", key)
        offset = (forecast.get("city") or {}).get("timezone", 0)
        buckets = {}
        order = []
        for entry in forecast.get("list") or []:
            stamp = entry.get("dt")
            if stamp is None:
                continue
            day = _day_key(stamp, offset)
            main = entry.get("main") or {}
            weather = (entry.get("weather") or [{}])[0]
            if day not in buckets:
                buckets[day] = {"lo": None, "hi": None, "desc": {}, "stamp": stamp + offset}
                order.append(day)
            bucket = buckets[day]
            low, high = main.get("temp_min"), main.get("temp_max")
            if low is not None:
                bucket["lo"] = low if bucket["lo"] is None else min(bucket["lo"], low)
            if high is not None:
                bucket["hi"] = high if bucket["hi"] is None else max(bucket["hi"], high)
            desc = (weather.get("description") or "").strip()
            if desc:
                bucket["desc"][desc] = bucket["desc"].get(desc, 0) + 1
        for day in order[:5]:
            bucket = buckets[day]
            label = time.strftime("%a", time.gmtime(bucket["stamp"]))
            desc = max(bucket["desc"].items(), key=lambda kv: kv[1])[0] if bucket["desc"] else ""
            days.append({"label": label, "lo": bucket["lo"], "hi": bucket["hi"], "desc": desc})
    except Exception as exc:
        errors.append("forecast: " + str(exc)[:50])

    return now, days, errors


def snapshot(force=False):
    with _lock:
        age = time.time() - _cache["at"]
        if not force and _cache["now"] and age < TTL:
            return _cache["now"], _cache["days"], int(age), _cache["errors"]
        now, days, errors = _refresh()
        if now or days:
            _cache.update({"now": now or _cache["now"], "days": days or _cache["days"],
                           "errors": errors, "at": time.time()})
            return _cache["now"], _cache["days"], 0, errors
        _cache["errors"] = errors
        return _cache["now"], _cache["days"], int(age), errors


def _round(value):
    return "-" if value is None else str(int(round(value)))


def lines_for(now, days, age, errors):
    out = ["AGE %d" % age]
    if now:
        out.append("EXTRA %s %s %s" % (
            _round(now.get("humidity")), _round(now.get("wind")), now.get("place") or "-"))
        out.append("CUR %s %s %s" % (
            _round(now.get("temp")), _round(now.get("feels")), now.get("desc") or "-"))
    for day in days:
        out.append("D %s %s %s %s" % (
            day["label"], _round(day["lo"]), _round(day["hi"]), day["desc"] or "-"))
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
                now, days, age, errors = snapshot(force=(verb == "REFRESH"))
                for line in lines_for(now, days, age, errors):
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


def prime():
    try:
        snapshot()
    except Exception:
        pass


if __name__ == "__main__":
    threading.Thread(target=prime, daemon=True).start()
    Server((BIND, PORT), Handler).serve_forever()
