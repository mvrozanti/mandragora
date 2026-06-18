import json
import subprocess
import sys
from pathlib import Path

THEME = Path.home() / ".config/rofi/themes/menu.rasi"
SCALES = ["1.0", "1.25", "1.5", "1.75", "2.0"]


def hypr(*args):
    return subprocess.run(
        ["hyprctl", *args],
        capture_output=True,
        text=True,
        check=False,
    )


def monitors():
    proc = hypr("-j", "monitors", "all")
    if proc.returncode != 0:
        return []
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []


def connected(mons):
    return [m for m in mons if not m.get("disabled")]


def logical_size(m):
    scale = m.get("scale", 1.0) or 1.0
    return round(m["width"] / scale), round(m["height"] / scale)


def apply(name, mode, pos, scale, extra=""):
    spec = f"{name},{mode},{pos},{scale}{extra}"
    hypr("keyword", "monitor", spec)


def current_mode(m):
    return f"{m['width']}x{m['height']}@{m['refreshRate']:.2f}Hz"


def reapply(m, *, mode=None, pos=None, scale=None):
    mode = mode if mode is not None else current_mode(m)
    pos = pos if pos is not None else f"{m['x']}x{m['y']}"
    scale = scale if scale is not None else f"{m.get('scale', 1.0)}"
    apply(m["name"], mode, pos, scale)


def notify(msg):
    subprocess.Popen(
        ["notify-send", "-a", "monitor", "-i", "video-display", "Display", msg],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def rofi(prompt, lines, *, mesg=None, width="40%", rows=12):
    args = [
        "rofi",
        "-dmenu",
        "-i",
        "-p",
        prompt,
        "-theme",
        str(THEME),
        "-theme-str",
        f"window {{ width: {width}; }} listview {{ lines: {rows}; }}",
        "-format",
        "i",
        "-markup-rows",
    ]
    if mesg:
        args += ["-mesg", mesg]
    proc = subprocess.run(
        args, input="\n".join(lines), capture_output=True, text=True, check=False
    )
    if proc.returncode != 0:
        return None
    out = proc.stdout.strip()
    return int(out) if out.isdigit() else None


def waybar():
    mons = monitors()
    conn = connected(mons)
    if len(mons) < 2:
        print(json.dumps({"text": "", "class": "hidden", "tooltip": ""}))
        return 0
    tip = ["<b>Displays</b>", ""]
    for m in mons:
        lw, lh = logical_size(m)
        state = "off" if m.get("disabled") else f"{lw}x{lh} @{m['x']},{m['y']}"
        mark = "" if m.get("disabled") else ""
        tip.append(f"{mark}  {m['name']}  —  {state}")
    tip.append("")
    tip.append("<i>click — arranger · right — on/off · mid — menu</i>")
    print(
        json.dumps(
            {
                "text": "󰍺",
                "class": "active",
                "tooltip": "\n".join(tip),
            }
        )
    )
    return 0


def pick_monitor(mons, prompt, *, allow_back=False):
    rows = []
    for m in mons:
        lw, lh = logical_size(m)
        tag = "  (off)" if m.get("disabled") else f"  {lw}x{lh}"
        focus = " " if m.get("focused") else ""
        rows.append(f"{m['name']}{tag}{focus}")
    if allow_back:
        rows.append("  back")
    idx = rofi(prompt, rows)
    if idx is None:
        return None
    if allow_back and idx == len(mons):
        return "__back__"
    if 0 <= idx < len(mons):
        return mons[idx]
    return None


def action_resolution(m):
    modes = m.get("availableModes", [])
    if not modes:
        notify(f"{m['name']}: no modes reported")
        return
    seen = []
    for mode in modes:
        if mode not in seen:
            seen.append(mode)
    idx = rofi(f"{m['name']} res", seen, rows=16)
    if idx is None:
        return
    reapply(m, mode=seen[idx])
    notify(f"{m['name']} → {seen[idx]}")


def action_scale(m):
    cur = str(m.get("scale", 1.0))
    rows = [(s + "  (current)" if s == cur else s) for s in SCALES]
    idx = rofi(f"{m['name']} scale", rows)
    if idx is None:
        return
    reapply(m, scale=SCALES[idx])
    notify(f"{m['name']} scale → {SCALES[idx]}")


def action_position(m, mons):
    others = [o for o in connected(mons) if o["name"] != m["name"]]
    if not others:
        notify("no other active display")
        return
    rels = []
    plan = []
    for o in others:
        lw, lh = logical_size(o)
        rels.append(f"  right of {o['name']}")
        plan.append((o["x"] + lw, o["y"]))
        rels.append(f"  left of {o['name']}")
        my_lw, _ = logical_size(m)
        plan.append((o["x"] - my_lw, o["y"]))
        rels.append(f"  above {o['name']}")
        my_lw, my_lh = logical_size(m)
        plan.append((o["x"], o["y"] - my_lh))
        rels.append(f"  below {o['name']}")
        plan.append((o["x"], o["y"] + lh))
    idx = rofi(f"place {m['name']}", rels, rows=12)
    if idx is None:
        return
    x, y = plan[idx]
    reapply(m, pos=f"{x}x{y}")
    notify(f"{m['name']} moved to {x},{y}")


def action_primary(m, mons):
    reapply(m, pos="0x0")
    x = logical_size(m)[0]
    for o in connected(mons):
        if o["name"] == m["name"]:
            continue
        reapply(o, pos=f"{x}x0")
        x += logical_size(o)[0]
    notify(f"{m['name']} set as primary (0,0)")


def action_mirror(m, mons):
    others = [o for o in connected(mons) if o["name"] != m["name"]]
    if not others:
        return
    rows = [f"  mirror {o['name']}" for o in others]
    idx = rofi(f"{m['name']} mirror", rows)
    if idx is None:
        return
    src = others[idx]["name"]
    apply(m["name"], "highres", "auto", str(m.get("scale", 1.0)), extra=f",mirror,{src}")
    notify(f"{m['name']} mirrors {src}")


def action_toggle(m, mons):
    if m.get("disabled"):
        apply(m["name"], "highres", "auto", "1")
        notify(f"{m['name']} enabled")
        return
    if len(connected(mons)) <= 1:
        notify("cannot disable the only active display")
        return
    hypr("keyword", "monitor", f"{m['name']},disable")
    notify(f"{m['name']} disabled")


def extend_all(mons):
    x = 0
    for m in connected(mons):
        reapply(m, pos=f"{x}x0")
        x += logical_size(m)[0]
    notify("extended left → right")


def mirror_all(mons):
    conn = connected(mons)
    if len(conn) < 2:
        return
    primary = next((m for m in conn if m["x"] == 0 and m["y"] == 0), conn[0])
    for m in conn:
        if m["name"] == primary["name"]:
            continue
        apply(m["name"], "highres", "auto", "1", extra=f",mirror,{primary['name']}")
    notify(f"all mirror {primary['name']}")


def monitor_actions(m, mons):
    while True:
        rows = [
            "  resolution",
            "  scale",
            "  reposition",
            "  set as primary",
            "  mirror another",
            ("  enable" if m.get("disabled") else "  disable"),
            "  back",
        ]
        idx = rofi(m["name"], rows, mesg=f"<b>{m['name']}</b> display settings")
        if idx is None or idx == 6:
            return
        if idx == 0:
            action_resolution(m)
        elif idx == 1:
            action_scale(m)
        elif idx == 2:
            action_position(m, mons)
        elif idx == 3:
            action_primary(m, mons)
        elif idx == 4:
            action_mirror(m, mons)
        elif idx == 5:
            action_toggle(m, mons)
        mons = monitors()
        m = next((x for x in mons if x["name"] == m["name"]), None)
        if m is None:
            return


def pick():
    mons = monitors()
    if len(mons) < 2:
        notify("only one display connected")
        return 0
    while True:
        rows = ["  extend (left → right)", "  mirror all", "──────────"]
        offset = len(rows)
        for m in mons:
            lw, lh = logical_size(m)
            tag = "(off)" if m.get("disabled") else f"{lw}x{lh}"
            focus = " " if m.get("focused") else ""
            rows.append(f"  {m['name']}  —  {tag}{focus}")
        idx = rofi("displays", rows, mesg="<b>Display arrangement</b>", rows=14)
        if idx is None:
            return 0
        if idx == 0:
            extend_all(mons)
            return 0
        if idx == 1:
            mirror_all(mons)
            return 0
        if idx == 2:
            continue
        m = mons[idx - offset]
        monitor_actions(m, mons)
        mons = monitors()


def power_toggle():
    mons = monitors()
    enabled = connected(mons)
    primary = next(
        (m for m in enabled if m["x"] == 0 and m["y"] == 0),
        enabled[0] if enabled else None,
    )
    secondaries = [
        m for m in mons if not primary or m["name"] != primary["name"]
    ]
    if not secondaries:
        notify("only one display connected")
        return 0
    if any(m.get("disabled") for m in secondaries):
        hypr("reload")
        notify("secondary monitor(s) on")
    else:
        for m in secondaries:
            hypr("keyword", "monitor", f"{m['name']},disable")
        notify("secondary monitor(s) off")
    return 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "pick"
    if cmd == "waybar":
        return waybar()
    if cmd == "toggle":
        return power_toggle()
    return pick()


if __name__ == "__main__":
    sys.exit(main())
