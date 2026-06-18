import json
import os
import re
import socket
import subprocess
import threading
import time

DRM = "/sys/class/drm"
DEBUG = os.environ.get("AUDIO_FOLLOW_DEBUG") == "1"

_state_lock = threading.Lock()
_timer_lock = threading.Lock()
_timer = None
SINK_MAP = {}


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=False).stdout


def sink_index_to_name():
    out = {}
    for line in run(["pactl", "list", "sinks", "short"]).splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            out[parts[0]] = parts[1]
    return out


def build_sink_map():
    idx2name = sink_index_to_name()
    names = list(idx2name.values())
    mapping = {}
    try:
        entries = os.listdir(DRM)
    except OSError:
        return mapping
    for entry in entries:
        if "-HDMI-A-" not in entry and "-DP-" not in entry:
            continue
        base = f"{DRM}/{entry}"
        try:
            with open(f"{base}/status") as fh:
                if fh.read().strip() != "connected":
                    continue
        except OSError:
            continue
        conn = re.sub(r"^card\d+-", "", entry)
        card = entry.split("-", 1)[0]
        try:
            pci = os.path.basename(os.path.realpath(f"{DRM}/{card}/device"))
        except OSError:
            continue
        dom_bus_dev = pci.rsplit(".", 1)[0].replace(":", "_")
        token = f"pci-{dom_bus_dev}."
        cands = [n for n in names if token in n]
        hdmi = [n for n in cands if "hdmi" in n.lower()]
        chosen = hdmi[0] if hdmi else (cands[0] if cands else None)
        if chosen:
            mapping[conn] = chosen
    return mapping


def monitor_id_to_name():
    try:
        mons = json.loads(run(["hyprctl", "-j", "monitors"]))
    except json.JSONDecodeError:
        return {}
    return {m["id"]: m["name"] for m in mons}


def pid_to_monitor_name():
    try:
        clients = json.loads(run(["hyprctl", "-j", "clients"]))
    except json.JSONDecodeError:
        return {}
    id2name = monitor_id_to_name()
    res = {}
    for c in clients:
        pid = c.get("pid")
        mon = c.get("monitor")
        if pid and pid > 0 and mon in id2name:
            res[pid] = id2name[mon]
    return res


def sink_inputs():
    idx2name = sink_index_to_name()
    out = run(["pactl", "list", "sink-inputs"])
    rows = []
    cur_idx = cur_sink = cur_pid = None

    def flush():
        if cur_idx is not None:
            rows.append((cur_idx, cur_pid, idx2name.get(cur_sink)))

    for line in out.splitlines():
        s = line.strip()
        head = re.match(r"Sink Input #(\d+)", s)
        if head:
            flush()
            cur_idx, cur_sink, cur_pid = head.group(1), None, None
            continue
        if s.startswith("Sink:"):
            cur_sink = s.split(":", 1)[1].strip()
        elif "application.process.id" in s:
            m = re.search(r'"(\d+)"', s)
            if m:
                cur_pid = int(m.group(1))
    flush()
    return rows


def read_ppid(pid):
    try:
        with open(f"/proc/{pid}/status") as fh:
            for line in fh:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (OSError, ValueError):
        return None
    return None


def resolve_monitor(pid, winmap):
    seen = 0
    while pid and pid > 1 and seen < 24:
        if pid in winmap:
            return winmap[pid]
        pid = read_ppid(pid)
        seen += 1
    return None


def log(msg):
    print(f"[audio-follow] {msg}", flush=True)


def reroute():
    with _state_lock:
        sink_map = dict(SINK_MAP)
    if not sink_map:
        return
    winmap = pid_to_monitor_name()
    for idx, pid, cur_sink in sink_inputs():
        if not pid:
            if DEBUG:
                log(f"stream {idx}: no pid, skipping")
            continue
        monname = resolve_monitor(pid, winmap)
        if not monname:
            if DEBUG:
                log(f"stream {idx} pid={pid}: no owning window, skipping")
            continue
        want = sink_map.get(monname)
        if want and want != cur_sink:
            log(f"stream {idx} pid={pid} -> {monname}: {cur_sink} => {want}")
            run(["pactl", "move-sink-input", idx, want])


def schedule():
    global _timer
    with _timer_lock:
        if _timer is not None:
            _timer.cancel()
        _timer = threading.Timer(0.15, reroute)
        _timer.daemon = True
        _timer.start()


def refresh_sink_map():
    global SINK_MAP
    new = build_sink_map()
    with _state_lock:
        SINK_MAP = new


def watch_pactl():
    while True:
        proc = subprocess.Popen(
            ["pactl", "subscribe"], stdout=subprocess.PIPE, text=True
        )
        for line in proc.stdout:
            if "sink-input" in line:
                schedule()
            elif "change" in line and "server" in line:
                schedule()
            elif "card" in line or "sink" in line:
                refresh_sink_map()
                schedule()
        time.sleep(1)


def watch_hypr():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        return
    xdg = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    path = f"{xdg}/hypr/{sig}/.socket2.sock"
    triggers = {
        "movewindow",
        "movewindowv2",
        "openwindow",
        "focusedmon",
        "workspace",
        "workspacev2",
        "windowtitle",
    }
    map_events = {"monitoradded", "monitoraddedv2", "monitorremoved"}
    while True:
        try:
            sock = socket.socket(socket.AF_UNIX)
            sock.connect(path)
        except OSError:
            time.sleep(2)
            continue
        with sock.makefile("r") as stream:
            for line in stream:
                ev = line.split(">>", 1)[0]
                if ev in map_events:
                    refresh_sink_map()
                    schedule()
                elif ev in triggers:
                    schedule()
        time.sleep(1)


def main():
    refresh_sink_map()
    log(f"sink map: {SINK_MAP}")
    reroute()
    threads = [
        threading.Thread(target=watch_pactl, daemon=True),
        threading.Thread(target=watch_hypr, daemon=True),
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
