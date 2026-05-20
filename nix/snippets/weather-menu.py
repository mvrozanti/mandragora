#!/usr/bin/env python3
import argparse
import html
import json
import math
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

KEY_FILE = Path("/run/secrets/weather/api_key")
CITY_ID = os.environ.get("WEATHER_CITY_ID", "3448439")
UNITS = "metric"
API = "https://api.openweathermap.org/data/2.5"

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "weather-menu"
CACHE_TTL = 600

ICONS = {
    "01d": "", "01n": "",
    "02d": "", "02n": "",
    "03d": "", "03n": "",
    "04d": "", "04n": "",
    "09d": "", "09n": "",
    "10d": "", "10n": "",
    "11d": "", "11n": "",
    "13d": "", "13n": "",
    "50d": "", "50n": "",
}

WIND_DIRS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


def icon_for(code: str) -> str:
    return ICONS.get(code, "")


def wind_dir(deg: float) -> str:
    return WIND_DIRS[int((deg + 22.5) % 360 // 45)]


def read_key() -> str | None:
    try:
        return KEY_FILE.read_text().strip() or None
    except OSError:
        return None


def cache_path(name: str) -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    return CACHE_DIR / name


def fetch_json(url: str, params: dict, cache_name: str, force: bool) -> dict | None:
    p = cache_path(cache_name)
    if not force and p.exists() and time.time() - p.stat().st_mtime < CACHE_TTL:
        try:
            return json.loads(p.read_text())
        except (OSError, json.JSONDecodeError):
            pass
    try:
        r = requests.get(url, params=params, timeout=8)
        r.raise_for_status()
        data = r.json()
    except (requests.RequestException, ValueError) as exc:
        print(f"weather-menu: fetch failed: {exc}", file=sys.stderr)
        if p.exists():
            try:
                return json.loads(p.read_text())
            except (OSError, json.JSONDecodeError):
                return None
        return None
    p.write_text(json.dumps(data))
    return data


def fetch_current(key: str, force: bool) -> dict | None:
    return fetch_json(
        f"{API}/weather",
        {"id": CITY_ID, "units": UNITS, "appid": key},
        "current.json",
        force,
    )


def fetch_forecast(key: str, force: bool) -> dict | None:
    return fetch_json(
        f"{API}/forecast",
        {"id": CITY_ID, "units": UNITS, "appid": key},
        "forecast.json",
        force,
    )


def fmt_current(cur: dict) -> str:
    main = cur.get("main", {})
    weather = (cur.get("weather") or [{}])[0]
    wind = cur.get("wind", {})
    sys_ = cur.get("sys", {})
    city = cur.get("name", "")
    country = sys_.get("country", "")
    desc = weather.get("description", "").capitalize()
    icon = icon_for(weather.get("icon", ""))
    temp = round(main.get("temp", 0))
    feels = round(main.get("feels_like", 0))
    humidity = main.get("humidity", 0)
    wspeed = wind.get("speed", 0)
    wdeg = wind.get("deg", 0)
    sunrise = sys_.get("sunrise")
    sunset = sys_.get("sunset")
    suntimes = ""
    if sunrise and sunset:
        sr = datetime.fromtimestamp(sunrise).strftime("%H:%M")
        ss = datetime.fromtimestamp(sunset).strftime("%H:%M")
        suntimes = f"   {sr}    {ss}"
    loc = html.escape(f"{city}, {country}".strip(", "))
    return (
        f"<span size='xx-large' foreground='#f5b9a4'>{icon}</span>   "
        f"<b><span size='xx-large'>{temp}°C</span></b>   "
        f"<span foreground='#d0d0dc' size='large'>{html.escape(desc)}</span>\n"
        f"<span foreground='#a0a0b0' size='small'>"
        f"<span foreground='#f4b2e3'></span> {loc}  ·  "
        f"<span foreground='#f5b9a4'></span> feels {feels}°  ·  "
        f"<span foreground='#9bd1ff'></span> {humidity}%  ·  "
        f"<span foreground='#c6c6d0'></span> {wspeed:.1f} m/s {wind_dir(wdeg)}"
        f"{suntimes}</span>"
    )


def daily_summary(slots: list[dict]) -> tuple[float, float, str, float]:
    temps = [s["main"]["temp"] for s in slots]
    icons: dict[str, int] = {}
    pops: list[float] = []
    for s in slots:
        w = (s.get("weather") or [{}])[0]
        code = w.get("icon", "")[:2] + "d"
        icons[code] = icons.get(code, 0) + 1
        pops.append(s.get("pop", 0) or 0)
    dominant = max(icons.items(), key=lambda kv: kv[1])[0] if icons else ""
    return min(temps), max(temps), dominant, max(pops) if pops else 0


def fmt_rows(forecast: dict) -> list[str]:
    rows: list[str] = []
    tz_offset = forecast.get("city", {}).get("timezone", 0)
    by_day: dict[str, list[dict]] = {}
    for slot in forecast.get("list", []):
        dt = datetime.fromtimestamp(slot["dt"], tz=timezone.utc) + timedelta(seconds=tz_offset)
        slot["_dt"] = dt
        key = dt.strftime("%Y-%m-%d")
        by_day.setdefault(key, []).append(slot)

    today = next(iter(by_day))
    for day_key, slots in by_day.items():
        dt = slots[0]["_dt"]
        label = "Today" if day_key == today else dt.strftime("%a %d %b")
        tmin, tmax, dom_icon, pop = daily_summary(slots)
        pop_str = (
            f"   <span foreground='#9bd1ff'></span> {int(pop * 100)}%"
            if pop >= 0.1
            else ""
        )
        header = (
            f"<b>{label}</b>   "
            f"<span foreground='#f5b9a4' size='large'>{icon_for(dom_icon)}</span>   "
            f"<span foreground='#f08c7c'></span> <b>{round(tmax)}°</b>  "
            f"<span foreground='#9bd1ff'></span> <b>{round(tmin)}°</b>"
            f"{pop_str}"
        )
        rows.append(f"{header}\0nonselectable\x1ftrue")

        for slot in slots:
            dt = slot["_dt"]
            main = slot.get("main", {})
            w = (slot.get("weather") or [{}])[0]
            wind = slot.get("wind", {})
            temp = round(main.get("temp", 0))
            icon = icon_for(w.get("icon", ""))
            desc = w.get("description", "").capitalize()
            pop = slot.get("pop", 0) or 0
            pop_str = (
                f"   <span foreground='#9bd1ff'></span> {int(pop * 100)}%"
                if pop >= 0.1
                else ""
            )
            wind_str = (
                f"   <span foreground='#808090'></span> {wind.get('speed', 0):.0f} m/s"
            )
            time_str = dt.strftime("%H:%M")
            row = (
                f"  <span foreground='#a0a0b0'>{time_str}</span>   "
                f"<span foreground='#f5b9a4' size='large'>{icon}</span>   "
                f"<b>{temp}°</b>   "
                f"<span foreground='#c0c0cc'>{html.escape(desc)}</span>"
                f"{pop_str}"
                f"<span foreground='#808090'>{wind_str}</span>"
            )
            rows.append(f"{row}\0nonselectable\x1ftrue")
    return rows


def open_rofi(mesg: str, rows: list[str]) -> int:
    theme = Path.home() / ".config/rofi/themes/menu.rasi"
    proc = subprocess.run(
        [
            "rofi",
            "-dmenu",
            "-i",
            "-markup-rows",
            "-no-custom",
            "-p",
            "weather",
            "-theme",
            str(theme),
            "-theme-str",
            (
                "window { width: 34%; } "
                "listview { lines: 14; } "
                "entry { enabled: false; } "
                "inputbar { children: []; padding: 0; border: 0; background-color: transparent; } "
                "element { padding: 6px 10px; } "
                "element selected { background-color: #ffffff12; }"
            ),
            "-format",
            "i",
            "-mesg",
            mesg,
            "-kb-custom-1",
            "Alt+r",
        ],
        input="\n".join(rows),
        text=True,
    )
    return proc.returncode


def cmd_pick(force: bool) -> int:
    key = read_key()
    if not key:
        subprocess.run(["notify-send", "weather", "API key missing"])
        return 1
    cur = fetch_current(key, force)
    fc = fetch_forecast(key, force)
    if not cur or not fc:
        subprocess.run(["notify-send", "weather", "fetch failed"])
        return 1
    mesg = fmt_current(cur)
    rows = fmt_rows(fc)
    rc = open_rofi(mesg, rows)
    if rc == 10:
        return cmd_pick(force=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("pick", help="open weather forecast popup")
    p.add_argument("--refresh", action="store_true", help="bypass cache")
    sub.add_parser("refresh", help="prime cache")
    args = ap.parse_args()

    if args.cmd in (None, "pick"):
        return cmd_pick(force=bool(getattr(args, "refresh", False)))
    if args.cmd == "refresh":
        key = read_key()
        if not key:
            return 1
        fetch_current(key, force=True)
        fetch_forecast(key, force=True)
        return 0
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
