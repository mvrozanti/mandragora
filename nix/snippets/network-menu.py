import json
import subprocess
import sys
from pathlib import Path

THEME = Path.home() / ".config/rofi/themes/menu.rasi"
RUNDIR = Path("/run/net-failover")
WIFI_IF = "wlan0"
LAN_IF = "enp8s0"
SIGNAL_ICONS = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
IWD_BUS = "net.connman.iwd"
IWD_STATION = "net.connman.iwd.Station"
IWD_NETWORK = "net.connman.iwd.Network"
BAR_FLOORS = (-82, -74, -66, -58)


def run(args, inp=None, timeout=None):
    try:
        return subprocess.run(
            args,
            input=inp,
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout,
        )
    except (subprocess.SubprocessError, OSError):
        return subprocess.CompletedProcess(args, 1, "", "")


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


def busctl(*args, timeout=8):
    return run(
        ["busctl", "--system", "--no-pager", "--json=short", *args],
        timeout=timeout,
    )


def busctl_data(*args, timeout=8):
    proc = busctl(*args, timeout=timeout)
    if proc.returncode != 0:
        return None
    values = []
    for line in proc.stdout.splitlines():
        try:
            values.append(json.loads(line)["data"])
        except (ValueError, KeyError):
            return None
    return values


def station_path():
    base = Path("/sys/class/net") / WIFI_IF
    try:
        ifindex = (base / "ifindex").read_text().strip()
        phy = (base / "phy80211/index").read_text().strip()
    except OSError:
        return None
    return f"/net/connman/iwd/{phy}/{ifindex}"


def bars_from_strength(strength):
    dbm = strength / 100.0
    for idx, floor in enumerate(BAR_FLOORS):
        if dbm < floor:
            return idx
    return 4


def network_props(path):
    values = busctl_data(
        "get-property", IWD_BUS, path, IWD_NETWORK, "Name", "Type", "Connected"
    )
    if not values or len(values) != 3:
        return None
    return {
        "ssid": values[0],
        "security": values[1],
        "connected": bool(values[2]),
        "path": path,
    }


def wifi_networks():
    station = station_path()
    if not station:
        return []
    values = busctl_data("call", IWD_BUS, station, IWD_STATION, "GetOrderedNetworks")
    if not values or not values[0]:
        return []
    nets = []
    for entry in values[0][0]:
        props = network_props(entry[0])
        if not props:
            continue
        props["bars"] = bars_from_strength(entry[1])
        nets.append(props)
    return nets


def connected_ssid(nets):
    for n in nets:
        if n["connected"]:
            return n["ssid"]
    return None


def current_ssid():
    station = station_path()
    if not station:
        return None
    values = busctl_data(
        "get-property", IWD_BUS, station, IWD_STATION, "ConnectedNetwork"
    )
    if not values or not values[0]:
        return None
    props = network_props(values[0])
    return props["ssid"] if props else None


def station_call(method, timeout=8):
    station = station_path()
    if not station:
        return None
    return busctl_data("call", IWD_BUS, station, IWD_STATION, method, timeout=timeout)


def open_manager():
    subprocess.Popen(
        ["kitty", "--class", "impala", "-o", "close_on_child_death=yes", "-e", "impala"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


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
    ssid = current_ssid() if dev != LAN_IF or not net else None
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


def do_connect(net):
    result = busctl_data(
        "call", IWD_BUS, net["path"], IWD_NETWORK, "Connect", timeout=30
    )
    if result is not None:
        notify(f"Connected to {net['ssid']}")
        return
    notify(f"{net['ssid']} needs a passphrase — opening Wi-Fi manager")
    open_manager()


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
            ssid = n["ssid"]
            add(
                f"{icon}  {ssid}{mark}{lock}",
                lambda item=n: do_connect(item),
            )
        rows.append("──────────────────────────")
        actions.append(None)
        add("  Rescan", lambda: station_call("Scan"))
        if cur:
            add("󰖪  Disconnect Wi-Fi", lambda: station_call("Disconnect"))
        add("  Wi-Fi manager", open_manager)

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
