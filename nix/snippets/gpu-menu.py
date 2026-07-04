#!/usr/bin/env python3
import argparse
import html
import json
import os
import subprocess
import sys
import time
from pathlib import Path

LOCK_DIR = Path(os.environ.get("GPU_LOCK_DIR", "/dev/shm/gpu-lock"))
HOLDER_FILE = LOCK_DIR / "gpu.lock.holder"

ICON_IDLE = '<span font_family="Font Awesome 7 Free Solid"></span>'
ICON_LOCKED = '<span font_family="Font Awesome 7 Free Solid"></span>'


def read_holder():
    try:
        holder = json.loads(HOLDER_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    pid = holder.get("pid")
    if isinstance(pid, int):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return None
        except PermissionError:
            pass
    return holder


def holder_derived(holder):
    if not holder:
        return holder
    since = holder.get("since")
    expected = holder.get("expected_seconds")
    now = time.time()
    if isinstance(since, (int, float)):
        holder["held_for"] = max(0.0, now - since)
        if isinstance(expected, (int, float)):
            holder["expected_remaining"] = max(0.0, since + expected - now)
    return holder


def proc_cmdline(pid):
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return ""
    parts = [p.decode("utf-8", "replace") for p in raw.split(b"\x00") if p]
    return " ".join(parts)


def fmt_dur(seconds):
    if seconds is None:
        return "?"
    s = int(seconds)
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s // 3600}h{(s % 3600) // 60:02d}m"


def nvidia_gpu():
    try:
        out = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=utilization.gpu,memory.used,memory.total,"
                "temperature.gpu,power.draw,power.limit",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return None
    if out.returncode != 0:
        return None
    fields = [f.strip() for f in out.stdout.strip().split(",")]
    if len(fields) < 6:
        return None
    keys = ["util", "mem_used", "mem_total", "temp", "power", "power_limit"]
    result = {}
    for key, raw in zip(keys, fields):
        try:
            result[key] = float(raw)
        except ValueError:
            result[key] = None
    return result


def nvidia_procs():
    try:
        out = subprocess.run(
            [
                "nvidia-smi",
                "--query-compute-apps=pid,used_memory,process_name",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return []
    if out.returncode != 0:
        return []
    procs = []
    for line in out.stdout.strip().splitlines():
        cells = [c.strip() for c in line.split(",")]
        if len(cells) < 3:
            continue
        procs.append({"pid": cells[0], "mem": cells[1], "name": cells[2]})
    return procs


def cmd_waybar(_args):
    holder = holder_derived(read_holder())
    gpu = nvidia_gpu()

    util = gpu["util"] if gpu and gpu.get("util") is not None else None
    util_str = f"{int(util)}%" if util is not None else "-"

    if gpu is None:
        cls = "error"
    elif holder:
        cls = "locked"
    else:
        cls = "idle"

    icon = ICON_LOCKED if holder else ICON_IDLE
    text = f"{icon}  {util_str}"

    tip = []
    if holder:
        name = holder.get("name", "?")
        pid = holder.get("pid", "?")
        held = fmt_dur(holder.get("held_for"))
        tip.append(f"<b>GPU LOCKED</b> by {name}")
        tip.append(f"pid {pid} · held {held}")
        if "expected_remaining" in holder:
            tip.append(f"~{fmt_dur(holder['expected_remaining'])} remaining")
    else:
        tip.append("<b>GPU free</b> — no lock holder")
    tip.append("")
    if gpu:
        tip.append(f"util {util_str}")
        if gpu.get("mem_used") is not None and gpu.get("mem_total") is not None:
            tip.append(
                f"vram {int(gpu['mem_used'])} / {int(gpu['mem_total'])} MiB"
            )
        if gpu.get("temp") is not None:
            tip.append(f"temp {int(gpu['temp'])}°C")
        if gpu.get("power") is not None and gpu.get("power_limit") is not None:
            tip.append(
                f"power {int(gpu['power'])} / {int(gpu['power_limit'])} W"
            )
    else:
        tip.append("nvidia-smi unavailable")
    tip.append("")
    tip.append("<i>click — details</i>")

    payload = {
        "text": text,
        "tooltip": "\n".join(tip),
        "class": cls,
        "alt": cls,
    }
    print(json.dumps(payload), flush=True)
    return 0


def build_rows():
    holder = holder_derived(read_holder())
    gpu = nvidia_gpu()
    procs = nvidia_procs()
    rows = []

    if holder:
        name = html.escape(str(holder.get("name", "?")))
        pid = holder.get("pid", "?")
        held = fmt_dur(holder.get("held_for"))
        eta = ""
        if "expected_remaining" in holder:
            eta = f" · ~{fmt_dur(holder['expected_remaining'])} left"
        rows.append(f"  <b>LOCKED</b> by {name}  (pid {pid} · held {held}{eta})")
        cmd = proc_cmdline(pid)
        if cmd:
            short = cmd if len(cmd) <= 100 else cmd[:97] + "..."
            rows.append(f"     <i>{html.escape(short)}</i>")
    else:
        rows.append("  <b>FREE</b> — no gpu-lock holder")

    rows.append("")

    if gpu:
        util = gpu.get("util")
        rows.append(
            f"  utilization  {int(util)}%" if util is not None
            else "  utilization  -"
        )
        if gpu.get("mem_used") is not None and gpu.get("mem_total") is not None:
            used, total = int(gpu["mem_used"]), int(gpu["mem_total"])
            pct = int(100 * used / total) if total else 0
            rows.append(f"  vram         {used} / {total} MiB  ({pct}%)")
        if gpu.get("temp") is not None:
            rows.append(f"  temp         {int(gpu['temp'])}°C")
        if gpu.get("power") is not None and gpu.get("power_limit") is not None:
            rows.append(
                f"  power        {int(gpu['power'])} / {int(gpu['power_limit'])} W"
            )
    else:
        rows.append("  nvidia-smi unavailable")

    if procs:
        rows.append("")
        rows.append(f"  <b>compute processes</b> ({len(procs)})")
        for p in procs:
            name = html.escape(p["name"])
            if len(name) > 60:
                name = name[:57] + "..."
            rows.append(f"     pid {p['pid']}  {p['mem']} MiB  {name}")

    return rows


def cmd_pick(_args):
    theme = Path.home() / ".config/rofi/themes/menu.rasi"
    while True:
        rows = build_rows()
        mesg = "<b>Enter</b> close · <b>Alt+r</b> refresh"
        proc = subprocess.run(
            [
                "rofi",
                "-dmenu",
                "-i",
                "-p",
                "gpu",
                "-theme",
                str(theme),
                "-theme-str",
                "window { width: 46%; } listview { lines: 12; }",
                "-markup-rows",
                "-no-custom",
                "-kb-custom-1",
                "Alt+r",
                "-mesg",
                mesg,
            ],
            input="\n".join(rows),
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode == 10:
            continue
        return 0


def main():
    parser = argparse.ArgumentParser(prog="gpu-menu")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_waybar = sub.add_parser("waybar", help="emit waybar JSON")
    p_waybar.set_defaults(func=cmd_waybar)
    p_pick = sub.add_parser("pick", help="open rofi gpu status popup")
    p_pick.set_defaults(func=cmd_pick)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
