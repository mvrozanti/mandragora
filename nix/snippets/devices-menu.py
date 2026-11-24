import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

PHONE = "\U000F011C"
KINDLE = "\U000F05DA"
VPS = "\U000F048B"
HEADSET = "\U000F02CB"
DRIVE = "\U000F02CA"
BOLT = "\U000F140B"

LOW_BATTERY = 20
FULL_DRIVE = 90
KINDLE_BATTERY_TTL = 300

TAILNET = json.loads(Path(os.environ["DEVICES_TAILNET"]).read_text())
STATE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "devices-menu"
HEADSET_PIN = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "waybar" / "bluetooth-device"


def run(cmd, timeout=5):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


def emit(text, tooltip="", cls=""):
    print(json.dumps({"text": text, "tooltip": tooltip, "class": cls}, ensure_ascii=False))


def since(stamp):
    try:
        then = datetime.fromisoformat(stamp)
    except (TypeError, ValueError):
        return None
    if then.year < 2000:
        return None
    seconds = (datetime.now(timezone.utc) - then).total_seconds()
    if seconds < 90:
        return "just now"
    if seconds < 5400:
        return f"{int(seconds // 60)}m ago"
    if seconds < 129600:
        return f"{int(seconds // 3600)}h ago"
    return f"{int(seconds // 86400)}d ago"


def size(count):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if count < 1000:
            return f"{count:.0f} {unit}"
        count /= 1000
    return f"{count:.0f} PB"


def tailnet_peer(name):
    out = run(["tailscale", "status", "--json"])
    if not out:
        return None
    ip = TAILNET[name]["ip"]
    for peer in (json.loads(out).get("Peer") or {}).values():
        if ip in peer.get("TailscaleIPs", []):
            return peer
    return None


def presence(peer):
    if peer is None:
        return False, "not on the tailnet"
    if peer.get("Online"):
        route = f"direct {peer['CurAddr']}" if peer.get("CurAddr") else f"relayed via {peer.get('Relay') or '?'}"
        return True, f"online · {route}"
    seen = since(peer.get("LastSeen"))
    return False, f"offline · last seen {seen}" if seen else "offline"


def battery_text(level, charging):
    if level is None:
        return ""
    return f" {level}%" + (f" {BOLT}" if charging else "")


def battery_class(online, level, charging):
    if not online:
        return "offline"
    if level is not None and level <= LOW_BATTERY and not charging:
        return "low"
    return ""


def kdeconnect_battery():
    ids = run(["kdeconnect-cli", "-a", "--id-only"])
    for device in (ids or "").split():
        path = f"/modules/kdeconnect/devices/{device}/battery"
        props = []
        for prop in ("charge", "isCharging"):
            out = run(["busctl", "--user", "--json=short", "get-property", "org.kde.kdeconnect", path, "org.kde.kdeconnect.device.battery", prop])
            props.append(json.loads(out)["data"] if out else None)
        if props[0] is not None and props[0] >= 0:
            return props[0], bool(props[1])
    return None, False


def phone():
    online, line = presence(tailnet_peer("phone"))
    level, charging = kdeconnect_battery()
    tip = ["Phone", line]
    tip.append(f"battery {level}%" + (" · charging" if charging else "") if level is not None else "battery unknown (KDE Connect not reachable)")
    emit(PHONE + battery_text(level, charging), "\n".join(tip), battery_class(online, level, charging))


def kindle_battery(online):
    cache = STATE / "kindle-battery.json"
    try:
        cached = json.loads(cache.read_text())
    except (OSError, ValueError):
        cached = None
    if online and (cached is None or time.time() - cached["at"] > KINDLE_BATTERY_TTL):
        out = run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=4", "-o", "StrictHostKeyChecking=accept-new",
             f"root@{TAILNET['kindle']['ip']}",
             "lipc-get-prop com.lab126.powerd battLevel; lipc-get-prop com.lab126.powerd isCharging"],
            timeout=8,
        )
        values = (out or "").split()
        if len(values) == 2 and all(v.isdigit() for v in values):
            cached = {"at": time.time(), "level": int(values[0]), "charging": values[1] == "1"}
            STATE.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps(cached))
    return cached


def kindle():
    online, line = presence(tailnet_peer("kindle"))
    battery = kindle_battery(online)
    tip = ["Kindle", line]
    if battery:
        age = since(datetime.fromtimestamp(battery["at"], timezone.utc).isoformat())
        tip.append(f"battery {battery['level']}%" + (" · charging" if battery["charging"] else "") + f" (read {age})")
    tip.append("click: sync now · right-click: shell")
    level = battery["level"] if battery and online else None
    charging = bool(battery and battery["charging"])
    emit(KINDLE + battery_text(level, charging), "\n".join(tip), battery_class(online, level, charging))


def vps():
    peer = tailnet_peer("vps")
    online, line = presence(peer)
    tip = ["VPS · mandragora-vps", line]
    if peer and online:
        tip.append(f"rx {size(peer.get('RxBytes', 0))} · tx {size(peer.get('TxBytes', 0))}")
    tip.append("click: ssh")
    emit(VPS, "\n".join(tip), "" if online else "down")


def bluez_objects():
    out = run(["busctl", "--json=short", "call", "org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"])
    if not out:
        return {}
    data = json.loads(out)["data"]
    return data[0] if data else {}


def prop(ifaces, iface, name):
    value = ifaces.get(iface, {}).get(name)
    return value["data"] if value else None


def headset_target(objects):
    try:
        pinned = HEADSET_PIN.read_text().strip().upper()
    except OSError:
        pinned = ""
    paired = [ifaces for ifaces in objects.values() if prop(ifaces, "org.bluez.Device1", "Paired")]
    for ifaces in paired:
        if pinned and prop(ifaces, "org.bluez.Device1", "Address") == pinned:
            return ifaces
    for ifaces in paired:
        if (prop(ifaces, "org.bluez.Device1", "Icon") or "").startswith("audio-"):
            return ifaces
    return None


def has_sink(address):
    sinks = run(["pactl", "list", "short", "sinks"]) or ""
    node = "bluez_output." + address.replace(":", "_")
    return any(len(fields) > 1 and fields[1].startswith(node) for fields in (line.split() for line in sinks.splitlines()))


def headset():
    objects = bluez_objects()
    if not objects:
        emit(HEADSET, "Headset\nbluetooth is off", "offline")
        return
    ifaces = headset_target(objects)
    if ifaces is None:
        emit("")
        return
    name = prop(ifaces, "org.bluez.Device1", "Alias") or "Headset"
    address = prop(ifaces, "org.bluez.Device1", "Address")
    if not prop(ifaces, "org.bluez.Device1", "Connected"):
        emit(HEADSET, f"{name}\ndisconnected\nclick: connect · right-click: blueman", "offline")
        return
    level = prop(ifaces, "org.bluez.Battery1", "Percentage")
    if not has_sink(address):
        emit(HEADSET + battery_text(level, False), f"{name}\nconnected, but no audio sink\nclick: disconnect", "nosink")
        return
    tip = [name, "connected · audio sink up"]
    if level is not None:
        tip.append(f"battery {level}%")
    tip.append("click: disconnect · right-click: blueman")
    emit(HEADSET + battery_text(level, False), "\n".join(tip), battery_class(True, level, False))


def mounts(node):
    for point in node.get("mountpoints") or []:
        if point:
            yield point, node
    for child in node.get("children") or []:
        yield from mounts(child)


def drives():
    out = run(["lsblk", "-J", "-b", "-o", "NAME,TRAN,RM,SIZE,MOUNTPOINTS,FSAVAIL,FSSIZE,FSUSE%,MODEL"])
    disks = [disk for disk in (json.loads(out)["blockdevices"] if out else []) if disk.get("tran") == "usb" and disk.get("size")]
    if not disks:
        emit("")
        return
    tip = ["External drives"]
    full = False
    for disk in disks:
        model = (disk.get("model") or disk["name"]).strip() + (" (removable)" if disk.get("rm") else "")
        rows = list(mounts(disk))
        if not rows:
            tip.append(f"{model} · not mounted")
        for point, node in rows:
            used = int((node.get("fsuse%") or "0%").rstrip("%"))
            full = full or used >= FULL_DRIVE
            tip.append(f"{model} · {point} · {size(node.get('fsavail') or 0)} free of {size(node.get('fssize') or 0)}")
    tip.append("click: open /mnt")
    emit(f"{DRIVE} {len(disks)}", "\n".join(tip), "low" if full else "")


TILES = {"phone": phone, "kindle": kindle, "vps": vps, "headset": headset, "drives": drives}


def main():
    if len(sys.argv) != 3 or sys.argv[1] != "waybar" or sys.argv[2] not in TILES:
        print(f"usage: devices-menu waybar {{{'|'.join(TILES)}}}", file=sys.stderr)
        sys.exit(2)
    TILES[sys.argv[2]]()


if __name__ == "__main__":
    main()
