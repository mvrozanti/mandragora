#!/usr/bin/env python3
import json
import re
import subprocess
import time

import evdev

DEVICE_NAME = "keyd virtual keyboard"
ALT_KEYS = {evdev.ecodes.KEY_LEFTALT, evdev.ecodes.KEY_RIGHTALT}
MATCH_RE = re.compile(r"[Bb]attlefield|[Bb][Ff]4")
AIM_SENSITIVITY = "-0.67"


def find_device():
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


def is_bf4_focused():
    proc = subprocess.run(
        ["hyprctl", "activewindow", "-j"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        return False
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return False
    cls = data.get("class") or ""
    title = data.get("title") or ""
    return bool(MATCH_RE.search(f"{cls} {title}"))


def set_sensitivity(value):
    subprocess.run(
        ["hyprctl", "keyword", "input:sensitivity", value],
        capture_output=True,
    )


def run():
    aim_on = False
    while True:
        path = find_device()
        if not path:
            time.sleep(2)
            continue
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            time.sleep(2)
            continue
        try:
            for event in dev.read_loop():
                if event.type != evdev.ecodes.EV_KEY or event.code not in ALT_KEYS:
                    continue
                if event.value == 1 and not aim_on and is_bf4_focused():
                    set_sensitivity(AIM_SENSITIVITY)
                    aim_on = True
                elif event.value == 0 and aim_on:
                    set_sensitivity("0")
                    aim_on = False
        except OSError:
            pass
        finally:
            if aim_on:
                set_sensitivity("0")
                aim_on = False
            dev.close()


if __name__ == "__main__":
    run()
