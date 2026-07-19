import json
import re
import subprocess
import sys
from pathlib import Path

THEME = Path.home() / ".config/rofi/themes/menu.rasi"
RUNDIR = Path("/run/net-failover")
WIFI_IF = "wlan0"
LAN_IF = "enp8s0"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
SIGNAL_ICONS = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]


def run(args, inp=None, timeout=None):
    return subprocess.run(
        args,
        input=inp,
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout,
    )


def notify(msg):
    subprocess.Popen(
        ["notify-send", "-a", "network", "-i", "network-wireless", "Network", msg],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def read_run(name, default=""):
    try:
        return (RUNDIR / name).read_text().strip()
    except OSError:
        return default


def default_iface():
    proc = run(["ip", "route", "show", "default"])
    for line in proc.stdout.splitlines():
        parts = line.split()
        if "dev" in parts:
            return parts[parts.index("dev") + 1]
    return None


def online():
    for target in ("8.8.8.8", "1.1.1.1"):
        if run(["ping", "-c1", "-W1", target]).returncode == 0:
            return True
    return False


def wifi_networks():
    proc = run(["iwctl", "station", WIFI_IF, "get-networks"], timeout=10)
    nets = []
    for raw in proc.stdout.splitlines():
        line = ANSI.sub("", raw).rstrip()
        stripped = line.strip()
        connected = stripped.startswith(">")
        if connected:
            stripped = stripped[1:].strip()
        toks = stripped.split()
        if len(toks) < 3:
            continue
        signal = toks[-1]
        if not re.fullmatch(r"[*\-]+", signal):
            continue
        security = toks[-2]
        name = " ".join(toks[:-2])
        if not name:
            continue
        nets.append(
            {
                "ssid": name,
                "security": security,
                "bars": min(signal.count("*"), 4),
                "connected": connected,
            }
        )
    return nets


def connected_ssid(nets):
    for n in nets:
        if n["connected"]:
            return n["ssid"]
    return None


def rofi(prompt, lines, *, mesg=None, width="34%", rows=14, password=False):
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
        "-markup-rows",
    ]
    if password:
        args += ["-password"]
    else:
        args += ["-format", "i"]
    if mesg:
        args += ["-mesg", mesg]
    proc = run(args, inp="\n".join(lines))
    if proc.returncode != 0:
        return None
    out = proc.stdout.strip()
    if password:
        return out
    return int(out) if out.isdigit() else None


def waybar():
    dev = default_iface()
    net = online()
    state = read_run("state")
    if not net:
        icon, cls = "󰖪", "offline"
    elif dev == WIFI_IF or state.startswith("wifi"):
        icon, cls = "", "hotspot"
    elif dev == LAN_IF:
        icon, cls = "󰈀", "online"
    else:
        icon, cls = "", "online"
    mode = read_run("mode", "auto")
    ssid = connected_ssid(wifi_networks()) if dev != LAN_IF or not net else None
    tip = ["<b>Network</b>", ""]
    tip.append(f"uplink   {state or ('online via ' + str(dev)) if net else 'offline'}")
    tip.append(f"mode     {mode}")
    if ssid:
        tip.append(f"wi-fi    {ssid}")
    tip.append("")
    tip.append("<i>click — switch · right — wi-fi manager</i>")
    print(json.dumps({"text": icon, "class": cls, "tooltip": "\n".join(tip)}))
    return 0


def prefer(mode):
    proc = run(["sudo", "-n", "net-prefer", mode])
    if proc.returncode == 0:
        notify({"lan": "Uplink → Ethernet", "wifi": "Uplink → Wi-Fi", "auto": "Uplink → Auto (failover)"}[mode])
    else:
        notify("Could not change uplink preference")


def do_connect(ssid, security):
    if security == "open":
        proc = run(["iwctl", "station", WIFI_IF, "connect", ssid], timeout=20)
    else:
        proc = run(["iwctl", "station", WIFI_IF, "connect", ssid], timeout=8)
        if proc.returncode != 0:
            pw = rofi(f"Passphrase for {ssid}", [], mesg=f"<b>{ssid}</b> needs a passphrase", password=True)
            if not pw:
                return
            proc = run(
                ["iwctl", "--passphrase", pw, "station", WIFI_IF, "connect", ssid],
                timeout=25,
            )
    if proc.returncode == 0:
        notify(f"Connected to {ssid}")
    else:
        notify(f"Failed to connect to {ssid}")


def pick():
    while True:
        mode = read_run("mode", "auto")
        state = read_run("state")
        nets = wifi_networks()
        cur = connected_ssid(nets)
        rows = []
        actions = []

        def add(label, fn):
            rows.append(label)
            actions.append(fn)

        add(f"󰈀  Ethernet — use LAN{'  ' if mode == 'lan' else ''}", lambda: prefer("lan"))
        add(f"  Wi-Fi — use hotspot{'  ' if mode == 'wifi' else ''}", lambda: prefer("wifi"))
        add(f"  Auto — failover{'  ' if mode == 'auto' else ''}", lambda: prefer("auto"))
        rows.append("─────────  wi-fi  ─────────")
        actions.append(None)
        for n in nets:
            icon = SIGNAL_ICONS[n["bars"]]
            lock = "  󰌾" if n["security"] != "open" else ""
            mark = "  " if n["connected"] else ""
            ssid, sec = n["ssid"], n["security"]
            add(
                f"{icon}  {ssid}{mark}{lock}",
                lambda s=ssid, x=sec: do_connect(s, x),
            )
        rows.append("──────────────────────────")
        actions.append(None)
        add("  Rescan", lambda: run(["iwctl", "station", WIFI_IF, "scan"]))
        if cur:
            add("󰖪  Disconnect Wi-Fi", lambda: run(["iwctl", "station", WIFI_IF, "disconnect"]))
        add("  Wi-Fi manager", lambda: subprocess.Popen(
            ["kitty", "--class", "impala", "-o", "close_on_child_death=yes", "-e", "impala"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ))

        online_via = state or ("online" if online() else "offline")
        mesg = f"<b>Network</b>   uplink: {online_via} · mode: {mode}"
        idx = rofi("network", rows, mesg=mesg, rows=min(len(rows) + 1, 18))
        if idx is None:
            return 0
        if not (0 <= idx < len(actions)) or actions[idx] is None:
            continue
        actions[idx]()
        if "Rescan" in rows[idx]:
            continue
        return 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "pick"
    if cmd == "waybar":
        return waybar()
    return pick()


if __name__ == "__main__":
    sys.exit(main())
