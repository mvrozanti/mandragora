from __future__ import annotations

import fcntl
import hashlib
import http.client
import json
import os
import re
import shutil
import signal
import socket
import ssl
import stat
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = os.environ.get("PHONE_BRIDGE_HOST", "0.0.0.0")
PORT = int(os.environ.get("PHONE_BRIDGE_PORT", "6688"))
MUSIC_DIR = Path(os.environ.get("PHONE_BRIDGE_MUSIC_DIR", "~/Music")).expanduser()
STATE_DIR = Path(os.environ.get("PHONE_BRIDGE_STATE", "~/.local/state/phone-bridge")).expanduser()
SERVICES_JSON = os.environ.get("PHONE_BRIDGE_SERVICES_JSON")
TAILNET_JSON = os.environ.get("PHONE_BRIDGE_TAILNET_JSON")
MPD_HOST = os.environ.get("PHONE_BRIDGE_MPD_HOST", "127.0.0.1")
MPD_PORT = int(os.environ.get("PHONE_BRIDGE_MPD_PORT", "6600"))
WPCTL = os.environ.get("PHONE_BRIDGE_WPCTL", "wpctl")
PLAYERCTL = os.environ.get("PHONE_BRIDGE_PLAYERCTL", "playerctl")
SYSTEMCTL = os.environ.get("PHONE_BRIDGE_SYSTEMCTL", "systemctl")
SWITCH_LOCK = os.environ.get("PHONE_BRIDGE_SWITCH_LOCK") or str(Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "mandragora-switch.lock")
UPTIME_FILE = os.environ.get("PHONE_BRIDGE_UPTIME", "/proc/uptime")
POWER_ACTIONS = ("reboot", "poweroff")
MEDIA_FORMAT = "{{playerInstance}}\t{{status}}\t{{title}}\t{{artist}}\t{{xesam:url}}\t{{position}}\t{{mpris:length}}\t{{mpris:artUrl}}"
MEDIA_ACTIONS = ("play-pause", "play", "pause", "next", "previous", "seek")
MEDIA_HIDDEN = re.compile(r"(mpd|kdeconnect|playerctld)(\.|$)")
MEDIA_ART_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}
MEDIA_ART_MAX = 5 * 1024 * 1024
STT_URL = os.environ.get("PHONE_BRIDGE_STT_URL", "http://127.0.0.1:8091/transcribe")
STT_MAX = 25 * 1024 * 1024
STT_BASE = STT_URL.rsplit("/", 1)[0]
STT_PROXIED = {("GET", "status"), ("POST", "warmup")}
STT_TASKS = ("transcribe", "translate")
STT_SUFFIXES = {"audio/mp4": ".m4a", "audio/aac": ".aac", "audio/ogg": ".ogg", "audio/webm": ".webm", "audio/wav": ".wav"}
LRCLIB_GET = "https://lrclib.net/api/get"
USER_AGENT = "mandragora-phone-bridge/1 (+https://github.com/mvrozanti/mandragora)"
VERSION = 1
PORTS = {"mpd": MPD_PORT, "ytdl": 6685, "theme": 6684, "mympd": 6680, "bridge": PORT, "code": 4096, "claude": 4097, "ask": 6689, "plugin": 6691, "stt": 8091}
LEASE_FILE = STATE_DIR / "lease.json"
LRCLIB_MISS_TTL = 24 * 3600
LRCLIB_RETRY_AFTER = 10 * 60
PHONE_LEASE_TTL = 60
AUDIO_SUFFIXES = {".mp3", ".m4a", ".flac", ".wav", ".ogg", ".opus", ".aac", ".wma"}
MIRROR_SUFFIXES = AUDIO_SUFFIXES | {".lrc"}
AUDIO_TYPES = {".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".aac": "audio/aac", ".flac": "audio/flac", ".ogg": "audio/ogg", ".opus": "audio/ogg", ".wav": "audio/wav", ".wma": "audio/x-ms-wma"}
MONEY_CACHE = Path(os.environ.get("PHONE_BRIDGE_MONEY_CACHE", "~/.local/state/money-menu/cache.json")).expanduser()
MONEY_CACHE_VERSION = 2
MONEY_STALE_AFTER = 20 * 60
MONEY_REFRESH_UNIT = "money-menu-refresh.service"
STATUS_PROBES_URL = os.environ.get("PHONE_BRIDGE_STATUS_PROBES", "https://status.mvr.ac/api/status-probes")
STATUS_VPS_URL = os.environ.get("PHONE_BRIDGE_STATUS_VPS", "https://status.mvr.ac/api/vps")
GPU_STATUS_URL = os.environ.get("PHONE_BRIDGE_GPU_STATUS", "http://127.0.0.1:6684/api/gpu")
NVIDIA_SMI = os.environ.get("PHONE_BRIDGE_NVIDIA_SMI", "/run/current-system/sw/bin/nvidia-smi")
GPU_LOCK = os.environ.get("PHONE_BRIDGE_GPU_LOCK", "/run/current-system/sw/bin/gpu-lock")
OLLAMA_URL = os.environ.get("PHONE_BRIDGE_OLLAMA", "http://127.0.0.1:11434")
STT_UNIT = "stt-core.service"
IDENTITY_JSON = os.environ.get("PHONE_BRIDGE_IDENTITY_JSON")
PHONE_AUDIT_MAX = 64
HUB_TTL = 20
APP_DIR = Path(os.environ.get("PHONE_BRIDGE_APP_DIR", "~/.local/share/mandragora-phone/app")).expanduser()
APP_APK = APP_DIR / "mandragora-phone.apk"
APP_META = APP_DIR / "app.json"
OPENCODE_PASSWORD_FILE = Path(os.environ.get("PHONE_BRIDGE_OPENCODE_PASSWORD", "~/.local/state/opencode/server-password")).expanduser()
CLAUDE_PASSWORD_FILE = Path(os.environ.get("PHONE_BRIDGE_CLAUDE_PASSWORD", "~/.local/state/claude-bridge/server-password")).expanduser()
CODE_BACKENDS = (
    ("claude", "Claude Code", "claude", "claude", CLAUDE_PASSWORD_FILE),
    ("opencode", "OpenCode", "code", "opencode", OPENCODE_PASSWORD_FILE),
)
PHONE_MEDIA_DIR = STATE_DIR / "phone-media"
PHONE_MEDIA_FILE_MAX = 8 << 30
PHONE_MEDIA_THUMB_MAX = 4 << 20
PHONE_MEDIA_INDEX_MAX = 64 << 20
PHONE_MEDIA_ID = re.compile(r"^[0-9]{1,19}$")
PHONE_MEDIA_SHA = re.compile(r"^[0-9a-f]{64}$")
PHONE_MEDIA_FIELDS = ("name", "path", "kind", "mime", "size", "taken", "modified")
PHONE_MEDIA_JOBS = ("thumbs", "pull", "remove")
PHONE_MEDIA_PEERS = os.environ.get("PHONE_BRIDGE_MEDIA_PEERS")
PHONE_MEDIA_PHONE_PATHS = ("/api/phone/media/index", "/api/phone/media/jobs", "/api/phone/media/thumb", "/api/phone/media/file", "/api/phone/media/report")
PHONE_AUDIT_FILE = STATE_DIR / "phone-audit.json"
PHONE_ONLY_POSTS = {"/api/power": "only the phone may power the desktop off", "/api/phone/audit": "only the phone reports on itself", "/api/phone/notify": "only the phone forwards its notifications", "/api/phone/forward": "only the phone switches its notifications over the bridge; the desktop uses phone-forward"}
NOTIFY_SEND = os.environ.get("PHONE_BRIDGE_NOTIFY_SEND", "notify-send")
FORWARD_FILE = Path(os.environ.get("PHONE_BRIDGE_FORWARD_FILE") or STATE_DIR / "forward.json")
FORWARD_CHANGED = ["pkill", "-RTMIN+16", "-x", r"(\.waybar-wrapped|waybar)"]
PROC_ROOT = Path(os.environ.get("PHONE_BRIDGE_PROC", "/proc"))
DESK_TWINS = {"com.whatsapp": "whatsapp", "com.whatsapp.w4b": "whatsapp"}

SINK_LINE = re.compile(r"^\s*│\s*(?P<default>\*)?\s*(?P<id>\d+)\.\s+(?P<name>.+?)\s+\[vol:\s*(?P<vol>[\d.]+)(?P<muted>\s+MUTED)?\]\s*$")
LRC_LINE = re.compile(r"^\[(\d+):(\d+(?:\.\d+)?)\](.*)$")

volume_lock = threading.Lock()
lease_lock = threading.Lock()
lrclib_slot = threading.Semaphore(1)
lrclib_misses: dict[str, float] = {}
money_lock = threading.Lock()
money_last: dict | None = None
hub_lock = threading.Lock()
hub_cache: dict = {"at": 0.0, "payload": None, "refreshing": False}
INBOX_FILE = STATE_DIR / "inbox.json"
INBOX_KEEP = 300
INBOX_WAIT_MAX = 50
INBOX_SLICE = 2.0
INBOX_LEVELS = ("info", "alert")
inbox_cond = threading.Condition()
inbox_data: dict = {"next": 1, "read": 0, "items": []}
WATCH_HOST = os.environ.get("PHONE_BRIDGE_WATCH_HOST", "watch.mvr.ac")
WATCH_PREFIX = "/internal"
cover_lock = threading.Lock()
cover_cache: dict[str, tuple[bytes, str] | None] = {}
COVER_CACHE_SIZE = 8
phone_media_lock = threading.Lock()


def load_json(path: str | None, fallback):
    if not path:
        return fallback
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return fallback


def desktop_ip() -> str | None:
    tailnet = load_json(TAILNET_JSON, {})
    return (tailnet.get("desktop") or {}).get("ip")


def vps_ip() -> str | None:
    tailnet = load_json(TAILNET_JSON, {})
    return (tailnet.get("vps") or {}).get("ip")


def inbox_load() -> None:
    data = load_json(str(INBOX_FILE), None)
    if isinstance(data, dict) and isinstance(data.get("items"), list):
        inbox_data["items"] = data["items"][-INBOX_KEEP:]
        inbox_data["next"] = max(int(data.get("next") or 1), 1 + max((item["id"] for item in inbox_data["items"]), default=0))
        inbox_data["read"] = int(data.get("read") or 0)


def inbox_save() -> None:
    tmp = INBOX_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(inbox_data), encoding="utf-8")
    os.replace(tmp, INBOX_FILE)


def clipped(body: dict, key: str, limit: int) -> str | None:
    value = body.get(key)
    if value is None:
        return None
    text = str(value).strip()
    return text[:limit] if text else None


def inbox_post(body: dict) -> dict:
    text = clipped(body, "text", 4000)
    if not text:
        raise ValueError("text required")
    level = body.get("level") or "info"
    if level not in INBOX_LEVELS:
        raise ValueError(f"level must be one of {', '.join(INBOX_LEVELS)}")
    ref = body.get("ref")
    if ref is not None and (not isinstance(ref, dict) or len(json.dumps(ref)) > 512):
        raise ValueError("ref must be a small object")
    with inbox_cond:
        item = {
            "id": inbox_data["next"],
            "ts": time.time(),
            "title": clipped(body, "title", 120) or clipped(body, "source", 32) or "mandragora",
            "text": text,
            "source": clipped(body, "source", 32) or "desktop",
            "open": clipped(body, "open", 32),
            "link": clipped(body, "link", 500),
            "level": level,
            "ref": ref,
        }
        inbox_data["next"] += 1
        inbox_data["items"] = (inbox_data["items"] + [item])[-INBOX_KEEP:]
        inbox_save()
        inbox_cond.notify_all()
    print(f"inbox: #{item['id']} from {item['source']}: {item['title']}", flush=True)
    return {"id": item["id"]}


def firefox_profile_running(profile: str) -> bool:
    wanted = profile.encode()
    for entry in PROC_ROOT.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            argv = (entry / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        if any(flag == b"-P" and value == wanted for flag, value in zip(argv, argv[1:], strict=False)):
            return True
    return False


def phone_notify(body: dict) -> dict:
    package = clipped(body, "package", 200)
    title = clipped(body, "title", 200)
    text = clipped(body, "text", 2000)
    if not package or not (title or text):
        raise ValueError("a notification needs a package and a title or a text")
    app = clipped(body, "app", 80) or package
    if not forward_on():
        return {"shown": False, "reason": "phone notifications are off"}
    twin = DESK_TWINS.get(package)
    if twin and firefox_profile_running(twin):
        return {"shown": False, "reason": f"{app} is open on the desktop"}
    run([NOTIFY_SEND, "--app-name", app, "--icon", "phone", "--", title or app, text or ""])
    return {"shown": True}


def forward_on() -> bool:
    data = load_json(str(FORWARD_FILE), {})
    return not (isinstance(data, dict) and data.get("on") is False)


def forward_set(body: dict) -> dict:
    on = body.get("on")
    if not isinstance(on, bool):
        raise ValueError("on must be true or false")
    with inbox_cond:
        FORWARD_FILE.parent.mkdir(parents=True, exist_ok=True)
        tmp = FORWARD_FILE.with_name(FORWARD_FILE.name + ".bridge")
        tmp.write_text(json.dumps({"on": on}) + "\n", encoding="utf-8")
        os.replace(tmp, FORWARD_FILE)
        inbox_cond.notify_all()
    try:
        subprocess.run(FORWARD_CHANGED, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=False)
    except (OSError, subprocess.SubprocessError):
        pass
    print(f"forward: phone notifications {'on' if on else 'off'}", flush=True)
    return {"on": on}


app_seen: dict = {"mtime": None, "code": 0}


def published_version() -> int:
    try:
        mtime = APP_META.stat().st_mtime_ns
    except OSError:
        return 0
    if app_seen["mtime"] != mtime:
        meta = load_json(str(APP_META), None)
        app_seen.update(mtime=mtime, code=int(meta.get("versionCode") or 0) if isinstance(meta, dict) else 0)
    return app_seen["code"]


def inbox_view(after: int) -> dict:
    newer = [item for item in inbox_data["items"] if item["id"] > after]
    return {"items": newer[-100:], "last": inbox_data["next"] - 1, "read": inbox_data["read"], "app": published_version(), "forward": forward_on()}


def inbox_wait(query: dict) -> dict:
    after = int(query.get("after") or 0)
    wait = min(max(float(query.get("wait") or 0), 0.0), INBOX_WAIT_MAX)
    known = str(query.get("app") or "")
    forward = str(query.get("forward") or "")
    deadline = time.monotonic() + wait
    with inbox_cond:
        while True:
            view = inbox_view(after)
            remaining = deadline - time.monotonic()
            if view["items"] or remaining <= 0 or (known.isdigit() and view["app"] != int(known)) or (forward in ("0", "1") and view["forward"] != (forward == "1")):
                return view
            inbox_cond.wait(min(remaining, INBOX_SLICE))


def inbox_read(body: dict) -> dict:
    with inbox_cond:
        upto = min(int(body.get("upTo") or 0), inbox_data["next"] - 1)
        if upto > inbox_data["read"]:
            inbox_data["read"] = upto
            inbox_save()
            inbox_cond.notify_all()
        return {"read": inbox_data["read"]}


def inbox_drop(body: dict) -> dict:
    with inbox_cond:
        if body.get("id") is not None:
            target = int(body["id"])
            inbox_data["items"] = [item for item in inbox_data["items"] if item["id"] != target]
        else:
            upto = int(body.get("upTo") or 0)
            inbox_data["items"] = [item for item in inbox_data["items"] if item["id"] > upto]
        inbox_save()
        return {"left": len(inbox_data["items"])}


class PinnedHTTPS(http.client.HTTPSConnection):
    def __init__(self, host: str, addr: str):
        tls = ssl.create_default_context()
        super().__init__(host, 443, timeout=20, context=tls)
        self.tls = tls
        self.addr = addr

    def connect(self) -> None:
        raw = socket.create_connection((self.addr, self.port), self.timeout)
        self.sock = self.tls.wrap_socket(raw, server_hostname=self.host)


def watch_call(method: str, rest: str, query: str, body: bytes | None) -> tuple[int, bytes, str]:
    if not (rest == "healthz" or rest.startswith("api/")) or ".." in rest:
        raise ValueError("only watch's api is proxied")
    addr = vps_ip()
    if not addr:
        raise OSError("no vps address in the tailnet manifest")
    conn = PinnedHTTPS(WATCH_HOST, addr)
    try:
        path = f"{WATCH_PREFIX}/{rest}" + (f"?{query}" if query else "")
        headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        conn.request(method, path, body=body, headers=headers)
        response = conn.getresponse()
        return response.status, response.read(), response.getheader("Content-Type") or "application/json"
    finally:
        conn.close()


class MpdError(Exception):
    pass


def mpd_command(command: str) -> list[tuple[str, str]]:
    with socket.create_connection((MPD_HOST, MPD_PORT), timeout=5) as sock:
        fh = sock.makefile("rwb", buffering=0)
        banner = fh.readline()
        if not banner.startswith(b"OK MPD"):
            raise MpdError("no mpd banner")
        fh.write((command + "\n").encode("utf-8"))
        pairs: list[tuple[str, str]] = []
        while True:
            line = fh.readline()
            if not line:
                raise MpdError("connection closed")
            text = line.decode("utf-8", "replace").rstrip("\n")
            if text == "OK":
                return pairs
            if text.startswith("ACK "):
                raise MpdError(text)
            key, _, value = text.partition(": ")
            pairs.append((key, value))


def mpd_dict(command: str) -> dict[str, str]:
    return dict(mpd_command(command))


def mpd_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def mpd_now() -> dict:
    status = mpd_dict("status")
    song = mpd_dict("currentsong")
    return {
        "file": song.get("file"),
        "artist": song.get("Artist"),
        "title": song.get("Title"),
        "album": song.get("Album"),
        "duration": float(status["duration"]) if status.get("duration") else None,
        "elapsed": float(status["elapsed"]) if status.get("elapsed") else 0.0,
        "playing": status.get("state") == "play",
        "state": status.get("state"),
    }


def mpd_resume(file: str | None, elapsed: float, playing: bool) -> None:
    position = f"{max(0.0, elapsed):.1f}"
    status = mpd_dict("status")
    active = status.get("state") in ("play", "pause")
    song_id = None
    if file:
        song_id = mpd_dict(f"playlistfind file {mpd_quote(file)}").get("Id")
        if song_id is None:
            insert = f"addid {mpd_quote(file)}" + (" +0" if status.get("song") is not None else "")
            song_id = mpd_dict(insert).get("Id")
    if song_id is not None and active:
        mpd_command(f"seekid {song_id} {position}")
    elif song_id is not None:
        mpd_command(f"playid {song_id}")
        mpd_command(f"seekcur {position}")
    elif active:
        mpd_command(f"seekcur {position}")
    else:
        mpd_command("play")
        mpd_command(f"seekcur {position}")
    mpd_command("pause 0" if playing else "pause 1")


def read_exact(fh, length: int) -> bytes:
    chunks: list[bytes] = []
    remaining = length
    while remaining > 0:
        chunk = fh.read(remaining)
        if not chunk:
            raise MpdError("connection closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def mpd_picture(command: str, file: str) -> tuple[bytes, str | None] | None:
    with socket.create_connection((MPD_HOST, MPD_PORT), timeout=5) as sock:
        fh = sock.makefile("rwb", buffering=0)
        if not fh.readline().startswith(b"OK MPD"):
            raise MpdError("no mpd banner")
        fh.write(b"binarylimit 262144\n")
        while True:
            line = fh.readline()
            if not line:
                raise MpdError("connection closed")
            if line.startswith(b"OK") or line.startswith(b"ACK"):
                break
        data = bytearray()
        mime = None
        size = None
        while True:
            fh.write(f"{command} {mpd_quote(file)} {len(data)}\n".encode("utf-8"))
            chunk = None
            while True:
                line = fh.readline()
                if not line:
                    raise MpdError("connection closed")
                text = line.decode("utf-8", "replace").rstrip("\n")
                if text == "OK":
                    break
                if text.startswith("ACK "):
                    return None
                key, _, value = text.partition(": ")
                if key == "size":
                    size = int(value)
                elif key == "type":
                    mime = value
                elif key == "binary":
                    chunk = read_exact(fh, int(value))
                    fh.readline()
            if chunk is None or size is None:
                break
            data.extend(chunk)
            if len(data) >= size or not chunk:
                break
        return (bytes(data), mime) if data else None


def sniff_image(data: bytes) -> str:
    if data.startswith(b"\xff\xd8"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG"):
        return "image/png"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    return "application/octet-stream"


def cover_for(file: str) -> tuple[bytes, str] | None:
    if safe_track(file) is None:
        raise ValueError("file is outside the music directory")
    with cover_lock:
        if file in cover_cache:
            return cover_cache[file]
    found = mpd_picture("readpicture", file) or mpd_picture("albumart", file)
    result = (found[0], found[1] or sniff_image(found[0])) if found else None
    with cover_lock:
        if len(cover_cache) >= COVER_CACHE_SIZE:
            cover_cache.pop(next(iter(cover_cache)))
        cover_cache[file] = result
    return result


def run(args: list[str]) -> str:
    return subprocess.check_output(args, stderr=subprocess.STDOUT, timeout=5).decode("utf-8", "replace")


def sinks() -> list[dict]:
    out = run([WPCTL, "status"])
    result: list[dict] = []
    in_audio = False
    in_sinks = False
    for line in out.splitlines():
        stripped = line.strip(" │├└─")
        if stripped.startswith("Audio"):
            in_audio = True
            continue
        if stripped.startswith("Video") or stripped.startswith("Settings"):
            in_audio = False
            in_sinks = False
            continue
        if not in_audio:
            continue
        if stripped.startswith("Sinks:"):
            in_sinks = True
            continue
        if stripped.endswith(":") and stripped[:-1].isalpha():
            in_sinks = False
            continue
        if not in_sinks:
            continue
        match = SINK_LINE.match(line)
        if match:
            result.append({
                "id": int(match.group("id")),
                "name": match.group("name"),
                "volume": round(float(match.group("vol")) * 100),
                "muted": bool(match.group("muted")),
                "default": bool(match.group("default")),
            })
    return result


def volume_state() -> dict:
    all_sinks = sinks()
    default = next((s for s in all_sinks if s["default"]), all_sinks[0] if all_sinks else None)
    return {"sink": default, "sinks": all_sinks}


def set_volume(body: dict) -> dict:
    with volume_lock:
        sink = body.get("sink")
        target = str(int(sink)) if sink is not None else "@DEFAULT_AUDIO_SINK@"
        if sink is not None and body.get("default"):
            run([WPCTL, "set-default", target])
        if "volume" in body:
            level = max(0, min(100, int(body["volume"])))
            run([WPCTL, "set-volume", "-l", "1.0", target, f"{level}%"])
        elif "step" in body:
            step = max(-100, min(100, int(body["step"])))
            run([WPCTL, "set-volume", "-l", "1.0", target, f"{abs(step)}%{'+' if step >= 0 else '-'}"])
        if "muted" in body:
            run([WPCTL, "set-mute", target, "1" if body["muted"] else "0"])
        return volume_state()


def read_lease() -> dict:
    try:
        with open(LEASE_FILE, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def write_lease(lease: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = LEASE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(lease), encoding="utf-8")
    tmp.replace(LEASE_FILE)


def safe_now() -> dict | None:
    try:
        return mpd_now()
    except (OSError, MpdError, KeyError, ValueError):
        return None


def phone_lease_live(lease: dict, now: dict | None) -> bool:
    if lease.get("owner") != "phone":
        return False
    if now is not None and now.get("playing"):
        return False
    last = lease.get("heartbeat") or lease.get("since") or 0
    return time.time() - last < PHONE_LEASE_TTL


def desk_lease(now: dict | None, previous: dict) -> dict:
    now = now or {}
    return {
        "owner": "desk",
        "file": now.get("file", previous.get("file")),
        "elapsed": now.get("elapsed", previous.get("elapsed", 0.0)),
        "playing": now.get("playing", False),
        "artist": now.get("artist", previous.get("artist")),
        "title": now.get("title", previous.get("title")),
        "duration": now.get("duration", previous.get("duration")),
        "since": previous.get("since") if previous.get("owner") == "desk" else time.time(),
    }


def lease_state() -> dict:
    with lease_lock:
        lease = read_lease()
        now = safe_now()
        if phone_lease_live(lease, now):
            return lease
        settled = desk_lease(now, lease)
        if lease.get("owner") != "desk":
            write_lease(settled)
        return settled


def take_lease(body: dict) -> dict:
    owner = body.get("owner")
    if owner not in ("desk", "phone"):
        raise ValueError("owner must be desk or phone")
    with lease_lock:
        current = read_lease()
        if owner == "phone":
            try:
                now = mpd_now()
                if now.get("playing"):
                    mpd_command("pause 1")
            except (OSError, MpdError, KeyError, ValueError):
                now = {}
            file = body.get("file") or now.get("file") or current.get("file")
            lease = {
                "owner": "phone",
                "file": file,
                "elapsed": float(body.get("elapsed", now.get("elapsed", current.get("elapsed", 0.0)))),
                "playing": bool(body.get("playing", now.get("playing", False))),
                **song_tags(file, body, now or None, current),
                "since": time.time(),
                **({"device": body["device"]} if body.get("device") else {}),
            }
        else:
            playing = bool(body.get("playing", False))
            if phone_lease_live(current, safe_now()):
                file = body.get("file") or current.get("file")
                elapsed = float(body.get("elapsed", current.get("elapsed", 0.0)))
                mpd_resume(file, elapsed, playing)
            elif playing:
                mpd_command("pause 0")
            lease = desk_lease(safe_now(), {})
        write_lease(lease)
        return lease


def mpd_tags(file: str) -> dict:
    song = mpd_dict(f"find file {mpd_quote(file)}")
    return {
        "artist": song.get("Artist"),
        "title": song.get("Title"),
        "duration": float(song["duration"]) if song.get("duration") else None,
    }


def song_tags(file: str | None, body: dict, now: dict | None, previous: dict) -> dict:
    keys = ("artist", "title", "duration")
    tags = {key: body[key] for key in keys if key in body}
    if len(tags) == len(keys):
        return tags
    source: dict | None = None
    if now and now.get("file") == file:
        source = now
    elif previous.get("file") == file:
        source = previous
    elif file:
        try:
            source = mpd_tags(file)
        except (OSError, MpdError, ValueError):
            source = None
    for key in keys:
        tags.setdefault(key, (source or {}).get(key))
    return tags


def heartbeat(body: dict) -> dict:
    with lease_lock:
        lease = read_lease()
        now = safe_now()
        if lease.get("owner") != "phone" or (now is not None and now.get("playing")):
            settled = desk_lease(now, lease)
            write_lease(settled)
            return settled
        holder = lease.get("device")
        if holder and body.get("device") != holder:
            return lease
        if body.get("device") and not holder:
            lease["device"] = body["device"]
        previous = dict(lease)
        for key in ("file", "elapsed", "playing"):
            if key in body:
                lease[key] = body[key]
        lease.update(song_tags(lease.get("file"), body, now, previous))
        lease["heartbeat"] = time.time()
        write_lease(lease)
        return lease


def parse_lrc(text: str) -> list[dict]:
    lines: list[dict] = []
    for raw in text.splitlines():
        match = LRC_LINE.match(raw.strip())
        if not match:
            continue
        seconds = int(match.group(1)) * 60 + float(match.group(2))
        lines.append({"t": round(seconds, 2), "x": match.group(3).strip()})
    return lines


def safe_track(file: str) -> Path | None:
    candidate = (MUSIC_DIR / file).resolve()
    if MUSIC_DIR.resolve() not in candidate.parents:
        return None
    return candidate


def cache_record(file: str) -> dict | None:
    digest = hashlib.sha1(file.encode("utf-8")).hexdigest()
    return load_json(str(MUSIC_DIR / ".lyrics" / f"{digest}.json"), None)


def track_tags(file: str, record: dict | None) -> dict:
    if record and record.get("artist") and record.get("title"):
        return {"artist": record["artist"], "title": record["title"], "album": record.get("album") or "", "duration": record.get("duration")}
    try:
        info = mpd_dict(f"lsinfo {mpd_quote(file)}")
    except (OSError, MpdError):
        info = {}
    duration = float(info["duration"]) if info.get("duration") else None
    return {"artist": info.get("Artist", ""), "title": info.get("Title", ""), "album": info.get("Album", ""), "duration": duration}


def lrclib_fetch(tags: dict) -> dict | None:
    if not tags.get("artist") or not tags.get("title"):
        return {}
    params = {"artist_name": tags["artist"], "track_name": tags["title"]}
    if tags.get("album"):
        params["album_name"] = tags["album"]
    if tags.get("duration"):
        params["duration"] = str(int(round(tags["duration"])))
    request = urllib.request.Request(LRCLIB_GET + "?" + urllib.parse.urlencode(params), headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            return json.load(response)
    except urllib.error.HTTPError as err:
        return {} if err.code == 404 else None
    except (urllib.error.URLError, ValueError, TimeoutError, OSError):
        return None


def lyrics_for(file: str) -> dict:
    track = safe_track(file)
    if track is None:
        raise ValueError("file is outside the music directory")
    lrc_path = track.with_suffix(".lrc")
    if lrc_path.is_file():
        return {"synced": parse_lrc(lrc_path.read_text(encoding="utf-8", errors="replace")), "plain": None, "source": "lrc"}
    record = cache_record(file)
    plain = (record or {}).get("lyrics") or None
    if record and record.get("instrumental"):
        return {"synced": None, "plain": None, "source": "cache:instrumental"}
    missed_at = lrclib_misses.get(file)
    if missed_at and time.time() - missed_at < LRCLIB_MISS_TTL:
        return {"synced": None, "plain": plain, "source": "cache" if plain else "miss"}
    if not lrclib_slot.acquire(blocking=False):
        return {"synced": None, "plain": plain, "source": "cache" if plain else "busy"}
    try:
        found = lrclib_fetch(track_tags(file, record))
    finally:
        lrclib_slot.release()
    if found is None:
        lrclib_misses[file] = time.time() - LRCLIB_MISS_TTL + LRCLIB_RETRY_AFTER
        return {"synced": None, "plain": plain, "source": "cache" if plain else "miss"}
    synced_text = found.get("syncedLyrics")
    if synced_text and track.suffix.lower() in AUDIO_SUFFIXES:
        lrc_path.write_text(synced_text, encoding="utf-8")
        return {"synced": parse_lrc(synced_text), "plain": None, "source": "lrclib"}
    lrclib_misses[file] = time.time()
    plain = plain or found.get("plainLyrics") or None
    return {"synced": None, "plain": plain, "source": "cache" if record and record.get("lyrics") else ("lrclib:plain" if plain else "miss")}


def read_money_cache() -> dict | None:
    global money_last
    try:
        with open(MONEY_CACHE, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return money_last
    if isinstance(data, dict) and data.get("version") == MONEY_CACHE_VERSION:
        money_last = data
    return money_last


def unit_state(unit: str) -> str:
    try:
        done = subprocess.run(["systemctl", "--user", "is-active", unit], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    return done.stdout.strip() or "unknown"


def money_state() -> dict:
    with money_lock:
        data = read_money_cache()
    refreshing = unit_state(MONEY_REFRESH_UNIT) == "activating"
    if data is None:
        return {"total_usd": None, "venues": [], "fx": {}, "prices": {}, "error": "no cached balance yet", "stale": True, "refreshing": refreshing}
    payload = dict(data)
    payload["stale"] = time.time() - float(data.get("fetched_at") or 0) > MONEY_STALE_AFTER
    payload["refreshing"] = refreshing
    return payload


def start_money_refresh() -> dict:
    subprocess.run(["systemctl", "--user", "start", "--no-block", MONEY_REFRESH_UNIT], check=True, timeout=5)
    return {"started": True}


def fetch_json(url: str, timeout: int = 5):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except (urllib.error.URLError, ValueError, TimeoutError):
        return None


def hub_payload() -> dict:
    parts: dict = {}

    def grab(key: str, url: str) -> None:
        parts[key] = fetch_json(url)

    threads = [threading.Thread(target=grab, args=pair) for pair in (("probes", STATUS_PROBES_URL), ("vps", STATUS_VPS_URL), ("gpu", GPU_STATUS_URL))]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    manifest = load_json(SERVICES_JSON, {})
    services = [dict(entry) for entry in manifest.get("services", [])]
    probes = (parts.get("probes") or {}).get("hosts") or {}
    known = {entry.get("host") for entry in services}
    for host, row in probes.items():
        if host not in known and row.get("untiled"):
            services.append({"name": host.split(".")[0], "host": host, "group": "untiled", "desc": "served by caddy, no tile", "access": row.get("access") or "priv", "where": row.get("where") or "vps", "untiled": True})
    groups = list(manifest.get("groups", []))
    if any(entry.get("untiled") for entry in services):
        groups.append({"id": "untiled", "label": "served, no tile"})
    return {
        "ts": time.time(),
        "machines": manifest.get("machines", []),
        "groups": groups,
        "services": services,
        "health": {host: row["now"] for host, row in probes.items() if row.get("now")},
        "probed": parts.get("probes") is not None,
        "vps": parts.get("vps"),
        "gpu": parts.get("gpu"),
    }


def hub_state() -> dict:
    with hub_lock:
        cached = hub_cache["payload"]
        if cached is not None and (time.time() - hub_cache["at"] < HUB_TTL or hub_cache["refreshing"]):
            return cached
        hub_cache["refreshing"] = True
    try:
        payload = hub_payload()
        with hub_lock:
            hub_cache["at"] = time.time()
            hub_cache["payload"] = payload
    finally:
        with hub_lock:
            hub_cache["refreshing"] = False
    return payload


def app_state() -> dict:
    meta = load_json(str(APP_META), None)
    if not isinstance(meta, dict) or not APP_APK.is_file():
        return {"error": "no build published"}
    return meta


CGROUP_ROOT = Path(f"/sys/fs/cgroup/user.slice/user-{os.getuid()}.slice/user@{os.getuid()}.service")
PROTECTED_UNITS = ("phone-bridge", "pipewire", "wireplumber", "dbus", "xdg-", "hyprland", "polkit", "gcr-", "dconf", "session.slice", "init.scope")
load_lock = threading.Lock()
cpu_last: dict[str, tuple[int, float]] = {}


def read_int(path: Path) -> int:
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return 0


def pressure(name: str) -> dict:
    out: dict[str, float] = {}
    try:
        for line in (Path("/proc/pressure") / name).read_text().splitlines():
            kind, _, rest = line.partition(" ")
            for field in rest.split():
                key, _, value = field.partition("=")
                if key in ("avg10", "avg60"):
                    out[kind + key[3:]] = float(value)
    except (OSError, ValueError):
        pass
    return out


def meminfo() -> dict:
    wanted = {"MemTotal": "total", "MemAvailable": "available", "SwapTotal": "swapTotal", "SwapFree": "swapFree"}
    out: dict[str, int] = {}
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, _, rest = line.partition(":")
            if key in wanted:
                out[wanted[key]] = int(rest.split()[0]) * 1024
    except (OSError, ValueError, IndexError):
        pass
    return out


def protected_unit(rel: str) -> bool:
    return any(token in rel for token in PROTECTED_UNITS)


def unit_kind(unit: str) -> str:
    if unit.startswith("tmux-spawn-"):
        return "tmux pane"
    if unit.startswith("kitty-"):
        return "kitty window"
    if unit.endswith(".service"):
        return "service"
    if unit.startswith("app-"):
        return "app"
    return "scope"


def unit_title(unit: str) -> str:
    base = unit.rsplit(".", 1)[0]
    if unit.startswith("app-"):
        base = re.sub(r"-\d+$", "", base[4:]).rsplit(".", 1)[-1]
    return base


def heaviest_comm(cg: Path, limit: int = 48) -> tuple[str, int]:
    try:
        pids = [int(p) for p in (cg / "cgroup.procs").read_text().split()]
    except (OSError, ValueError):
        return "", 0
    best, best_rss = "", -1
    for pid in pids[:limit]:
        proc = Path("/proc") / str(pid)
        try:
            rss = int((proc / "statm").read_text().split()[1])
            comm = (proc / "comm").read_text().strip().rsplit("/", 1)[-1]
        except (OSError, ValueError, IndexError):
            continue
        if rss > best_rss:
            best, best_rss = comm, rss
    return best, len(pids)


def walk_units(root: Path, depth: int = 0):
    try:
        children = [p for p in root.iterdir() if p.is_dir()]
    except OSError:
        return
    for child in children:
        if child.name.endswith(".service") or child.name.endswith(".scope"):
            yield child
        elif depth < 3:
            yield from walk_units(child, depth + 1)


def cpu_usage(cg: Path) -> int:
    try:
        for line in (cg / "cpu.stat").read_text().splitlines():
            if line.startswith("usage_usec "):
                return int(line.split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return 0


def sample_units() -> list:
    now = time.monotonic()
    rows = []
    seen = set()
    for cg in walk_units(CGROUP_ROOT):
        rel = str(cg.relative_to(CGROUP_ROOT))
        if protected_unit(rel):
            continue
        usage = cpu_usage(cg)
        previous = cpu_last.get(rel)
        cpu_last[rel] = (usage, now)
        seen.add(rel)
        cpu = 0.0
        if previous and now > previous[1] and usage >= previous[0]:
            cpu = (usage - previous[0]) / ((now - previous[1]) * 1_000_000)
        rows.append((rel, cg, read_int(cg / "memory.current"), read_int(cg / "memory.swap.current"), cpu))
    for rel in list(cpu_last):
        if rel not in seen:
            del cpu_last[rel]
    return rows


def load_state() -> dict:
    with load_lock:
        if not cpu_last:
            sample_units()
            time.sleep(0.3)
        rows = sample_units()
    rows.sort(key=lambda r: r[2] + r[3], reverse=True)
    hogs = []
    for rel, cg, mem, swap, cpu in rows[:8]:
        comm, procs = heaviest_comm(cg)
        hogs.append({"id": rel, "unit": cg.name, "kind": unit_kind(cg.name), "name": comm or unit_title(cg.name), "mem": mem, "swap": swap, "cpu": round(cpu, 2), "procs": procs})
    return {
        "ts": time.time(),
        "pressure": {"memory": pressure("memory"), "cpu": pressure("cpu"), "io": pressure("io")},
        "memory": meminfo(),
        "hogs": hogs,
    }


def kill_unit(body: dict) -> dict:
    rel = str(body.get("id") or "").strip("/")
    if not rel or ".." in rel.split("/"):
        raise ValueError("id required")
    cg = CGROUP_ROOT / rel
    if not cg.is_dir() or not (cg.name.endswith(".service") or cg.name.endswith(".scope")):
        raise ValueError("unknown unit")
    if protected_unit(rel):
        raise ValueError("protected unit")
    name, procs = heaviest_comm(cg)
    killfile = cg / "cgroup.kill"
    if killfile.exists():
        killfile.write_text("1")
    else:
        for pid in (cg / "cgroup.procs").read_text().split():
            try:
                os.kill(int(pid), signal.SIGKILL)
            except (OSError, ValueError):
                pass
    return {"killed": rel, "name": name or unit_title(cg.name), "procs": procs}


def mib_bytes(text: str | None) -> int:
    try:
        return int(float((text or "").split()[0]) * 1024 * 1024)
    except (ValueError, IndexError):
        return 0


def first_number(text: str | None) -> float:
    try:
        return float((text or "").split()[0])
    except (ValueError, IndexError):
        return 0.0


def gpu_proc_name(raw: str) -> str:
    if "\\" in raw:
        return raw.rsplit("\\", 1)[-1]
    return (raw.split() or [""])[0].rsplit("/", 1)[-1]


def pid_unit(pid: int) -> str:
    try:
        line = (Path("/proc") / str(pid) / "cgroup").read_text().strip().splitlines()[-1]
    except (OSError, IndexError):
        return ""
    units = [part for part in line.split("/") if part.endswith(".service") or part.endswith(".scope")]
    return units[-1] if units else ""


def nvidia_state() -> tuple[dict | None, list[dict]]:
    try:
        done = subprocess.run([NVIDIA_SMI, "-q", "-x"], capture_output=True, text=True, timeout=8)
        root = ET.fromstring(done.stdout)
    except (OSError, subprocess.SubprocessError, ET.ParseError):
        return None, []
    gpu = root.find("gpu")
    if gpu is None:
        return None, []
    info = {
        "name": gpu.findtext("product_name") or "",
        "memUsed": mib_bytes(gpu.findtext("fb_memory_usage/used")),
        "memTotal": mib_bytes(gpu.findtext("fb_memory_usage/total")),
        "util": first_number(gpu.findtext("utilization/gpu_util")),
        "temp": first_number(gpu.findtext("temperature/gpu_temp")),
        "power": first_number(gpu.findtext("gpu_power_readings/instant_power_draw") or gpu.findtext("gpu_power_readings/power_draw")),
    }
    merged: dict[str, dict] = {}
    for proc in gpu.findall("processes/process_info"):
        try:
            pid = int(proc.findtext("pid") or "")
        except ValueError:
            continue
        name = gpu_proc_name(proc.findtext("process_name") or "") or f"pid {pid}"
        mem = mib_bytes(proc.findtext("used_memory"))
        row = merged.setdefault(name, {"pid": pid, "name": name, "kind": "graphics", "mem": 0, "unit": pid_unit(pid), "pids": []})
        if mem > row["mem"]:
            row["pid"] = pid
        row["mem"] += mem
        row["pids"].append(pid)
        if "C" in (proc.findtext("type") or ""):
            row["kind"] = "compute"
    return info, sorted(merged.values(), key=lambda row: row["mem"], reverse=True)


def lock_party(raw) -> dict | None:
    if not isinstance(raw, dict):
        return None
    expected = raw.get("expected_seconds")
    return {
        "name": str(raw.get("name") or "").removesuffix(" (unmanaged)"),
        "pid": int(raw.get("pid") or 0),
        "since": float(raw.get("since") or 0),
        "expected": float(expected) if isinstance(expected, (int, float)) else None,
    }


def gpu_lock_state() -> dict:
    try:
        done = subprocess.run([GPU_LOCK, "status", "--json"], capture_output=True, text=True, timeout=8)
        data = json.loads(done.stdout or "{}")
    except (OSError, subprocess.SubprocessError, ValueError):
        return {"holder": None, "unmanaged": None, "error": "gpu-lock did not answer"}
    return {"holder": lock_party(data.get("holder")), "unmanaged": lock_party(data.get("unmanaged"))}


def ollama_models() -> list[dict]:
    data = fetch_json(f"{OLLAMA_URL}/api/ps", timeout=3)
    models = data.get("models") if isinstance(data, dict) else None
    rows = []
    for model in models or []:
        if isinstance(model, dict) and int(model.get("size_vram") or 0) > 0:
            rows.append({"kind": "ollama", "name": str(model.get("name") or model.get("model") or ""), "mem": int(model["size_vram"])})
    return rows


def stt_status() -> dict | None:
    data = fetch_json(f"{STT_BASE}/status", timeout=3)
    return data if isinstance(data, dict) else None


def stt_resident(status: dict | None, procs: list[dict]) -> dict | None:
    if not status or not status.get("model_loaded"):
        return None
    model = (status.get("config") or {}).get("model") or "whisper"
    return {"kind": "stt", "name": f"stt-core · {model}", "mem": sum(row["mem"] for row in procs if row["unit"] == STT_UNIT)}


def gpu_state() -> dict:
    found: dict = {}

    def grab(key: str, probe) -> None:
        found[key] = probe()

    probes = (("smi", nvidia_state), ("lock", gpu_lock_state), ("ollama", ollama_models), ("stt", stt_status))
    threads = [threading.Thread(target=grab, args=pair) for pair in probes]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    info, procs = found.get("smi") or (None, [])
    lock = found.get("lock") or {"holder": None, "unmanaged": None}
    holder_pid = (lock.get("holder") or {}).get("pid")
    outside_pid = (lock.get("unmanaged") or {}).get("pid")
    for row in procs:
        pids = row.pop("pids")
        row["holder"] = holder_pid in pids
        row["outside"] = outside_pid in pids
    residents = list(found.get("ollama") or [])
    stt = stt_resident(found.get("stt"), procs)
    if stt:
        residents.append(stt)
    return {"ts": time.time(), "gpu": info, "lock": lock, "procs": procs, "residents": residents}


def post_local(url: str, payload: dict | None, timeout: int = 30) -> dict:
    data = json.dumps(payload).encode("utf-8") if payload is not None else b""
    request = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read()
    try:
        parsed = json.loads(body or b"{}")
    except ValueError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def gpu_free(body: dict) -> dict:
    what = str(body.get("what") or "")
    if what == "stt":
        try:
            post_local(f"{STT_BASE}/release", None)
        except urllib.error.HTTPError as err:
            raise OSError(f"stt-core cannot release its model (HTTP {err.code})") from None
        except (urllib.error.URLError, TimeoutError):
            raise OSError("stt-core is not running on the desktop") from None
        return {"freed": "stt-core"}
    if what != "ollama":
        raise ValueError("what must be ollama or stt")
    name = str(body.get("name") or "")
    if name not in {row["name"] for row in ollama_models()}:
        raise ValueError(f"{name or 'that model'} is not in VRAM")
    try:
        post_local(f"{OLLAMA_URL}/api/generate", {"model": name, "keep_alive": 0})
    except (urllib.error.URLError, TimeoutError) as err:
        raise OSError(f"ollama did not unload {name}: {err}") from None
    return {"freed": name}


def media_state() -> dict:
    try:
        proc = subprocess.run([PLAYERCTL, "-a", "-f", MEDIA_FORMAT, "metadata"], capture_output=True, text=True, timeout=4)
    except (OSError, subprocess.SubprocessError):
        return {"players": []}
    players = []
    for line in proc.stdout.splitlines():
        name, status, title, artist, url, position, length, art = (line.split("\t") + [""] * 8)[:8]
        if not name or MEDIA_HIDDEN.match(name) or status not in ("Playing", "Paused"):
            continue
        source = "YouTube" if "youtube.com" in url or "youtu.be" in url else name.split(".")[0]
        players.append({
            "player": name,
            "status": status,
            "title": title,
            "artist": artist,
            "url": url,
            "source": source,
            "position": micros_to_seconds(position),
            "length": micros_to_seconds(length),
            "art": Path(art).name if media_art_path(art) else "",
        })
    players.sort(key=lambda p: p["status"] != "Playing")
    return {"players": players}


def micros_to_seconds(value: str) -> float:
    return int(value) / 1_000_000 if value.strip().isdigit() else 0.0


def media_art_path(art_url: str) -> Path | None:
    if not art_url.startswith("file://"):
        return None
    path = Path(urllib.parse.unquote(art_url[len("file://"):]))
    if path.suffix.lower() not in MEDIA_ART_TYPES or not path.is_file() or path.stat().st_size > MEDIA_ART_MAX:
        return None
    return path


def media_art(player: str) -> tuple[bytes, str] | None:
    if not re.fullmatch(r"[A-Za-z0-9._-]+", player) or MEDIA_HIDDEN.match(player):
        return None
    try:
        proc = subprocess.run([PLAYERCTL, "-p", player, "metadata", "mpris:artUrl"], capture_output=True, text=True, timeout=4)
    except (OSError, subprocess.SubprocessError):
        return None
    path = media_art_path(proc.stdout.strip())
    return (path.read_bytes(), MEDIA_ART_TYPES[path.suffix.lower()]) if path else None


def media_action(body: dict) -> dict:
    player = str(body.get("player") or "")
    action = str(body.get("action") or "play-pause")
    if action not in MEDIA_ACTIONS:
        raise ValueError("unknown action")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", player):
        raise ValueError("player required")
    args = [action]
    if action == "seek":
        try:
            position = float(str(body.get("position")))
        except (TypeError, ValueError):
            raise ValueError("position required") from None
        args = ["position", f"{max(position, 0.0):.3f}"]
    subprocess.run([PLAYERCTL, "-p", player, *args], capture_output=True, text=True, timeout=4, check=False)
    time.sleep(0.25)
    return media_state()


def transcribe_audio(data: bytes, content_type: str, task: str = "transcribe", language: str = "") -> dict:
    if not data:
        raise ValueError("empty audio")
    if task not in STT_TASKS:
        raise ValueError(f"task must be one of {', '.join(STT_TASKS)}")
    if language and not (language.isalpha() and len(language) <= 3):
        raise ValueError("language must be a short language code")
    kind = content_type.split(";")[0].strip() or "audio/mp4"
    boundary = os.urandom(12).hex()
    fields = {"task": task, **({"language": language} if language else {})}
    form = "".join(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n" for name, value in fields.items())
    head = form.encode() + (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"audio\"; filename=\"speech{STT_SUFFIXES.get(kind, '.m4a')}\"\r\n"
        f"Content-Type: {kind}\r\n\r\n"
    ).encode()
    request = urllib.request.Request(
        STT_URL,
        data=head + data + f"\r\n--{boundary}--\r\n".encode(),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            result = json.loads(response.read())
    except urllib.error.HTTPError as err:
        try:
            detail = json.loads(err.read()).get("detail")
        except (ValueError, AttributeError):
            detail = None
        raise OSError(str(detail or f"speech-to-text answered {err.code}")) from None
    except urllib.error.URLError:
        raise OSError("speech-to-text is not running on the desktop") from None
    return {
        "text": str(result.get("text") or "").strip(),
        "language": result.get("language"),
        "duration": result.get("duration"),
        "language_probability": result.get("language_probability"),
        "task": result.get("task") or task,
        "elapsed_seconds": result.get("elapsed_seconds"),
    }


def stt_call(method: str, rest: str, body: bytes | None, content_type: str) -> tuple[int, bytes, str]:
    if (method, rest) not in STT_PROXIED:
        raise ValueError("only stt-core's status and warmup are proxied")
    headers = {"Content-Type": content_type} if body is not None and content_type else {}
    request = urllib.request.Request(f"{STT_BASE}/{rest}", data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return response.status, response.read(), response.headers.get("Content-Type") or "application/json"
    except urllib.error.HTTPError as err:
        return err.code, err.read(), err.headers.get("Content-Type") or "application/json"
    except urllib.error.URLError:
        raise OSError("speech-to-text is not running on the desktop") from None


def read_password(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip() or None
    except OSError:
        return None


def code_access() -> dict:
    backends = [
        {"id": backend_id, "name": name, "port": PORTS[port_key], "user": user, "password": read_password(path)}
        for backend_id, name, port_key, user, path in CODE_BACKENDS
    ]
    return {"backends": backends}


def music_path(rel: str) -> Path:
    root = MUSIC_DIR.resolve()
    path = (root / rel).resolve()
    if root not in path.parents or path.suffix.lower() not in MIRROR_SUFFIXES or not path.is_file():
        raise ValueError("not a song in the library")
    return path


def mirrored(name: str) -> bool:
    return not name.startswith(".") and Path(name).suffix.lower() in MIRROR_SUFFIXES and "\n" not in name and "\t" not in name


def music_index() -> dict:
    root = MUSIC_DIR.resolve()
    files = []
    for folder, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(filter(mirrored, names)):
            path = Path(folder) / name
            try:
                info = path.lstat()
            except OSError:
                continue
            if stat.S_ISREG(info.st_mode):
                files.append([path.relative_to(root).as_posix(), info.st_size, int(info.st_mtime)])
    version = hashlib.sha256(json.dumps(files).encode("utf-8")).hexdigest()[:16]
    return {"version": version, "files": files}


def music_index_for(have: str | None) -> dict:
    index = music_index()
    if have and have == index["version"]:
        return {"version": index["version"], "unchanged": True}
    return index


def config() -> dict:
    return {
        "version": VERSION,
        "desktop": {"ip": desktop_ip(), "host": "mandragora-desktop"},
        "ports": PORTS,
        "music": {"dir": str(MUSIC_DIR)},
        "hub": load_json(SERVICES_JSON, {}),
        "code": code_access(),
        "phone": phone_expect(),
        "time": time.time(),
    }


def phone_expect() -> dict:
    identity = load_json(IDENTITY_JSON, {})
    apps = []
    for entry in identity.get("apps", []) if isinstance(identity, dict) else []:
        if isinstance(entry, dict) and entry.get("package"):
            package = str(entry["package"])
            apps.append({"package": package, "name": str(entry.get("name") or package), "unrestricted": bool(entry.get("unrestricted"))})
    return {"apps": apps}


def phone_audit_store(body: dict) -> dict:
    checks = body.get("checks")
    if not isinstance(checks, list) or len(checks) > PHONE_AUDIT_MAX:
        raise ValueError(f"checks must be a list of at most {PHONE_AUDIT_MAX}")
    clean = []
    for check in checks:
        if not isinstance(check, dict) or not check.get("id"):
            raise ValueError("every check needs an id")
        ok = check.get("ok")
        clean.append({
            "id": str(check["id"])[:80],
            "label": str(check.get("label") or "")[:200],
            "ok": ok if isinstance(ok, bool) else None,
            "detail": str(check.get("detail") or "")[:300],
        })
    report = {"ts": time.time(), "versionCode": int(body.get("versionCode") or 0), "checks": clean}
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = PHONE_AUDIT_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(report), encoding="utf-8")
    tmp.replace(PHONE_AUDIT_FILE)
    return {"stored": len(clean)}


def phone_audit_view() -> dict:
    report = load_json(str(PHONE_AUDIT_FILE), None)
    if not isinstance(report, dict):
        return {"ts": None, "age": None, "versionCode": 0, "checks": [], "failing": []}
    checks = [check for check in report.get("checks", []) if isinstance(check, dict)]
    return {
        "ts": report.get("ts"),
        "age": time.time() - float(report.get("ts") or 0),
        "versionCode": report.get("versionCode", 0),
        "checks": checks,
        "failing": [check.get("id") for check in checks if check.get("ok") is False],
    }


def media_peers() -> set[str]:
    if PHONE_MEDIA_PEERS is not None:
        return {peer.strip() for peer in PHONE_MEDIA_PEERS.split(",") if peer.strip()}
    phone = (load_json(TAILNET_JSON, {}).get("phone") or {}).get("ip")
    return {phone} if phone else set()


def phone_only(path: str, method: str) -> bool:
    if method == "POST" and path in PHONE_ONLY_POSTS:
        return True
    return path in PHONE_MEDIA_PHONE_PATHS and not (method == "GET" and path == "/api/phone/media/thumb")


def media_from_phone(path: str, method: str, client: str) -> bool:
    return not phone_only(path, method) or client in media_peers()


def switching() -> bool:
    try:
        with open(SWITCH_LOCK, "a") as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return True
            fcntl.flock(handle, fcntl.LOCK_UN)
            return False
    except OSError:
        return False


def power_state() -> dict:
    try:
        uptime = float(Path(UPTIME_FILE).read_text().split()[0])
    except (OSError, ValueError, IndexError):
        uptime = None
    return {"uptime": uptime, "switching": switching()}


def power(body: dict) -> dict:
    action = str(body.get("action") or "")
    if action not in POWER_ACTIONS:
        raise ValueError("action must be reboot or poweroff")
    if switching():
        raise ValueError("a switch is running; try again when it ends")
    done = subprocess.run([SYSTEMCTL, action], capture_output=True, text=True, timeout=15)
    if done.returncode != 0:
        raise OSError((done.stderr or done.stdout).strip() or f"systemctl {action} failed")
    return {"action": action}


def media_id(value) -> str:
    text = str(value if value is not None else "")
    if not PHONE_MEDIA_ID.match(text):
        raise ValueError("bad media id")
    return text


def media_ids(values) -> list[str]:
    if values is None:
        return []
    if not isinstance(values, list):
        raise ValueError("ids must be a list")
    return list(dict.fromkeys(media_id(v) for v in values))


def media_path(*parts: str) -> Path:
    return PHONE_MEDIA_DIR.joinpath(*parts)


def media_read(name: str, fallback):
    data = load_json(str(media_path(name)), None)
    return data if isinstance(data, type(fallback)) else fallback


def media_write(name: str, data) -> None:
    target = media_path(name)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    os.replace(tmp, target)


def media_jobs() -> dict:
    jobs = media_read("jobs.json", {})
    remove = jobs.get("remove")
    failed = jobs.get("failed")
    return {
        "thumbs": [str(x) for x in jobs.get("thumbs") or []],
        "pull": [str(x) for x in jobs.get("pull") or []],
        "remove": {str(k): str(v) for k, v in remove.items()} if isinstance(remove, dict) else {},
        "failed": failed if isinstance(failed, dict) else {},
    }


def media_held(mid: str) -> dict | None:
    meta = media_read(f"held/{mid}.json", {})
    return meta if meta.get("sha256") and media_path("held", mid).is_file() else None


def media_index_items() -> dict[str, dict]:
    return {item["id"]: item for item in media_read("index.json", {}).get("items") or [] if isinstance(item, dict) and "id" in item}


def media_for_phone() -> dict:
    with phone_media_lock:
        jobs = media_jobs()
        media_write("seen.json", {"at": time.time()})
    return {
        "thumbs": jobs["thumbs"],
        "pull": jobs["pull"],
        "remove": [{"id": mid, "sha256": sha} for mid, sha in jobs["remove"].items()],
        "reindex": not media_path("index.json").is_file(),
    }


def media_clean_item(item) -> dict:
    if not isinstance(item, dict):
        raise ValueError("index items must be objects")
    clean = {"id": media_id(item.get("id"))}
    for key in PHONE_MEDIA_FIELDS:
        if key in item:
            clean[key] = item[key]
    return clean


def media_store_index(body: dict) -> dict:
    items = body.get("items")
    if not isinstance(items, list):
        raise ValueError("items required")
    clean = [media_clean_item(item) for item in items]
    present = {item["id"] for item in clean}
    with phone_media_lock:
        media_write("index.json", {"at": time.time(), "items": clean})
        jobs = media_jobs()
        gone = [mid for mid in jobs["remove"] if mid not in present]
        for mid in gone:
            media_log(mid, jobs["remove"].pop(mid), "gone")
        jobs["thumbs"] = [mid for mid in jobs["thumbs"] if mid in present]
        jobs["pull"] = [mid for mid in jobs["pull"] if mid in present]
        media_write("jobs.json", jobs)
    return media_for_phone()


def media_log(mid: str, sha: str, outcome: str) -> None:
    item = media_index_items().get(mid) or {}
    line = json.dumps({"id": mid, "sha256": sha, "outcome": outcome, "name": item.get("name"), "path": item.get("path"), "at": time.time()})
    target = media_path("removed.jsonl")
    target.parent.mkdir(parents=True, exist_ok=True)
    with open(target, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def media_request(body: dict) -> dict:
    thumbs = media_ids(body.get("thumbs"))
    pull = media_ids(body.get("pull"))
    remove = media_ids(body.get("remove"))
    archived = body.get("archived") or {}
    if not isinstance(archived, dict) or not all(isinstance(v, str) and PHONE_MEDIA_SHA.match(v) for v in archived.values()):
        raise ValueError("archived maps ids to sha256")
    archived = {media_id(k): v for k, v in archived.items()}
    with phone_media_lock:
        jobs = media_jobs()
        missing = [mid for mid in remove if media_held(mid) is None]
        if missing:
            raise ValueError(f"not held on the desktop yet: {', '.join(missing)}")
        for mid in thumbs:
            jobs["failed"].pop(mid, None)
            if mid not in jobs["thumbs"] and not media_path("thumbs", f"{mid}.jpg").is_file():
                jobs["thumbs"].append(mid)
        for mid in pull:
            jobs["failed"].pop(mid, None)
            if mid not in jobs["pull"] and media_held(mid) is None:
                jobs["pull"].append(mid)
        for mid in remove:
            jobs["failed"].pop(mid, None)
            jobs["remove"][mid] = (media_held(mid) or {})["sha256"]
        for mid, sha in archived.items():
            jobs["failed"].pop(mid, None)
            jobs["remove"][mid] = sha
        media_write("jobs.json", jobs)
    return media_status()


def media_status() -> dict:
    held_dir = media_path("held")
    held = []
    if held_dir.is_dir():
        for meta in sorted(held_dir.glob("*.json")):
            found = media_held(meta.stem)
            if found:
                held.append(found)
    jobs = media_jobs()
    thumbs_dir = media_path("thumbs")
    return {
        "index": media_read("index.json", {"at": None, "items": []}),
        "jobs": {key: jobs[key] for key in PHONE_MEDIA_JOBS},
        "failed": jobs["failed"],
        "held": held,
        "thumbs": sorted(p.stem for p in thumbs_dir.glob("*.jpg")) if thumbs_dir.is_dir() else [],
        "seen": media_read("seen.json", {}).get("at"),
    }


def media_receive_thumb(mid: str, data: bytes) -> dict:
    mid = media_id(mid)
    if not data or len(data) > PHONE_MEDIA_THUMB_MAX or sniff_image(data) != "image/jpeg":
        raise ValueError("a thumbnail is a jpeg under 4 MiB")
    target = media_path("thumbs", f"{mid}.jpg")
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, target)
    with phone_media_lock:
        jobs = media_jobs()
        jobs["thumbs"] = [x for x in jobs["thumbs"] if x != mid]
        media_write("jobs.json", jobs)
    return {"id": mid}


def media_receive_file(mid: str, stream, length: int, claimed: str) -> dict:
    mid = media_id(mid)
    claimed = claimed.strip().lower()
    if not PHONE_MEDIA_SHA.match(claimed):
        raise ValueError("X-Sha256 header required")
    if length < 0 or length > PHONE_MEDIA_FILE_MAX:
        raise ValueError("bad length")
    held = media_path("held")
    held.mkdir(parents=True, exist_ok=True)
    partial = held / f"{mid}.part"
    digest = hashlib.sha256()
    remaining = length
    with open(partial, "wb") as fh:
        while remaining > 0:
            chunk = stream.read(min(1 << 16, remaining))
            if not chunk:
                break
            digest.update(chunk)
            fh.write(chunk)
            remaining -= len(chunk)
    if remaining or digest.hexdigest() != claimed:
        partial.unlink(missing_ok=True)
        raise ValueError("upload incomplete or sha256 mismatch")
    os.replace(partial, held / mid)
    item = media_index_items().get(mid) or {}
    meta = {"id": mid, "sha256": claimed, "size": length, "at": time.time(), **{k: item[k] for k in PHONE_MEDIA_FIELDS if k in item}}
    media_write(f"held/{mid}.json", meta)
    with phone_media_lock:
        jobs = media_jobs()
        jobs["pull"] = [x for x in jobs["pull"] if x != mid]
        media_write("jobs.json", jobs)
    return {"id": mid, "sha256": claimed}


def media_report(body: dict) -> dict:
    mid = media_id(body.get("id"))
    job = body.get("job")
    if job not in PHONE_MEDIA_JOBS:
        raise ValueError("job must be thumbs, pull or remove")
    error = body.get("error")
    with phone_media_lock:
        jobs = media_jobs()
        if job == "remove":
            sha = jobs["remove"].pop(mid, None)
            if sha is not None:
                media_log(mid, sha, f"failed: {error}" if error else "removed")
        else:
            jobs[job] = [x for x in jobs[job] if x != mid]
        if error:
            jobs["failed"][mid] = {"job": job, "error": str(error)[:300], "at": time.time()}
        media_write("jobs.json", jobs)
    return {"ok": True}


def media_release(body: dict) -> dict:
    ids = media_ids(body.get("ids"))
    released = []
    with phone_media_lock:
        jobs = media_jobs()
        for mid in ids:
            if mid in jobs["remove"]:
                continue
            media_path("held", mid).unlink(missing_ok=True)
            media_path("held", f"{mid}.json").unlink(missing_ok=True)
            released.append(mid)
    return {"released": released}


class Handler(BaseHTTPRequestHandler):
    server_version = "phone-bridge/1"

    def log_message(self, format, *args):
        print(f"{self.address_string()} {format % args}", flush=True)

    def send_json(self, payload, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_bytes(self, data: bytes, content_type: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "max-age=3600")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def send_song(self, path: Path) -> None:
        size = path.stat().st_size
        start, end, status = 0, size - 1, 200
        wanted = self.headers.get("Range") or ""
        if wanted.startswith("bytes="):
            first, _, last = wanted[6:].split(",")[0].strip().partition("-")
            try:
                if first:
                    start = int(first)
                    end = min(int(last), size - 1) if last else size - 1
                else:
                    start = max(0, size - int(last))
            except ValueError:
                start, end = 0, size - 1
            if start > end or start >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
            status = 206
        self.send_response(status)
        self.send_header("Content-Type", AUDIO_TYPES.get(path.suffix.lower(), "application/octet-stream"))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            with open(path, "rb") as fh:
                fh.seek(start)
                remaining = end - start + 1
                while remaining > 0:
                    chunk = fh.read(min(1 << 16, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def send_file(self, path: Path, content_type: str, filename: str) -> None:
        size = path.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            with open(path, "rb") as fh:
                shutil.copyfileobj(fh, self.wfile, 1 << 16)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def proxy_watch(self, method: str, url) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else (b"" if method in ("POST", "PATCH") else None)
        status, data, content_type = watch_call(method, url.path[len("/api/watch/"):], url.query, body)
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def proxy_stt(self, method: str, url) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        if length > STT_MAX:
            raise ValueError("audio too long")
        body = self.rfile.read(length) if method == "POST" else None
        status, data, content_type = stt_call(method, url.path[len("/api/stt/"):], body, self.headers.get("Content-Type") or "")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def read_body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except ValueError:
            data = dict(urllib.parse.parse_qsl(raw.decode("utf-8", "replace")))
        return data if isinstance(data, dict) else {}

    def refuse_stranger(self, path: str, method: str) -> bool:
        if media_from_phone(path, method, self.client_address[0]):
            return False
        self.close_connection = True
        self.send_json({"error": PHONE_ONLY_POSTS.get(path, "only the phone sends its media")}, 403)
        return True

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = dict(urllib.parse.parse_qsl(url.query))
        if self.refuse_stranger(url.path, "GET"):
            return
        try:
            if url.path == "/healthz":
                self.send_json({"ok": True})
            elif url.path == "/api/config":
                self.send_json(config())
            elif url.path == "/api/volume":
                self.send_json(volume_state())
            elif url.path == "/api/lease":
                self.send_json(lease_state())
            elif url.path == "/api/now":
                self.send_json(mpd_now())
            elif url.path == "/api/money":
                self.send_json(money_state())
            elif url.path == "/api/hub":
                self.send_json(hub_state())
            elif url.path == "/api/app":
                self.send_json(app_state())
            elif url.path == "/api/power":
                self.send_json(power_state())
            elif url.path == "/api/load":
                self.send_json(load_state())
            elif url.path == "/api/gpu":
                self.send_json(gpu_state())
            elif url.path == "/api/phone/audit":
                self.send_json(phone_audit_view())
            elif url.path == "/api/phone/forward":
                self.send_json({"on": forward_on()})
            elif url.path == "/api/media":
                self.send_json(media_state())
            elif url.path == "/api/media/art":
                found = media_art(query.get("player") or "")
                if found is None:
                    self.send_json({"error": "no art"}, 404)
                else:
                    self.send_bytes(found[0], found[1])
            elif url.path == "/api/inbox":
                self.send_json(inbox_wait(query))
            elif url.path.startswith("/api/watch/"):
                self.proxy_watch("GET", url)
            elif url.path.startswith("/api/stt/"):
                self.proxy_stt("GET", url)
            elif url.path == "/api/app/apk":
                if APP_APK.is_file():
                    self.send_file(APP_APK, "application/vnd.android.package-archive", APP_APK.name)
                else:
                    self.send_json({"error": "no build published"}, 404)
            elif url.path == "/api/lyrics":
                file = query.get("file")
                if not file:
                    self.send_json({"error": "file required"}, 400)
                else:
                    self.send_json(lyrics_for(file))
            elif url.path == "/api/file":
                self.send_song(music_path(query.get("file") or ""))
            elif url.path == "/api/music/index":
                self.send_json(music_index_for(query.get("have")))
            elif url.path == "/api/phone/media":
                self.send_json(media_status())
            elif url.path == "/api/phone/media/jobs":
                self.send_json(media_for_phone())
            elif url.path == "/api/phone/media/thumb":
                thumb = media_path("thumbs", f"{media_id(query.get('id'))}.jpg")
                if thumb.is_file():
                    self.send_bytes(thumb.read_bytes(), "image/jpeg")
                else:
                    self.send_json({"error": "no thumbnail"}, 404)
            elif url.path == "/api/phone/media/held":
                mid = media_id(query.get("id"))
                meta = media_held(mid)
                if meta is None:
                    self.send_json({"error": "not held"}, 404)
                else:
                    self.send_file(media_path("held", mid), str(meta.get("mime") or "application/octet-stream"), mid)
            elif url.path == "/api/cover":
                file = query.get("file")
                found = cover_for(file) if file else None
                if not file:
                    self.send_json({"error": "file required"}, 400)
                elif found is None:
                    self.send_json({"error": "no cover"}, 404)
                else:
                    self.send_bytes(found[0], found[1])
            else:
                self.send_json({"error": "not found"}, 404)
        except ValueError as err:
            self.send_json({"error": str(err)}, 400)
        except (OSError, MpdError, subprocess.SubprocessError, http.client.HTTPException) as err:
            self.send_json({"error": str(err)}, 503)

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        if self.refuse_stranger(url.path, "POST"):
            return
        if url.path.startswith("/api/stt/"):
            try:
                self.proxy_stt("POST", url)
            except ValueError as err:
                self.send_json({"error": str(err)}, 400)
            except OSError as err:
                self.send_json({"error": str(err)}, 503)
            return
        if url.path == "/api/transcribe":
            try:
                length = int(self.headers.get("Content-Length") or 0)
                if length > STT_MAX:
                    raise ValueError("audio too long")
                query = dict(urllib.parse.parse_qsl(url.query))
                audio = self.rfile.read(length)
                self.send_json(transcribe_audio(audio, self.headers.get("Content-Type") or "", query.get("task") or "transcribe", query.get("language") or ""))
            except ValueError as err:
                self.send_json({"error": str(err)}, 400)
            except OSError as err:
                self.send_json({"error": str(err)}, 503)
            return
        if url.path in ("/api/phone/media/thumb", "/api/phone/media/file"):
            self.receive_media(url)
            return
        try:
            if url.path.startswith("/api/watch/"):
                self.proxy_watch("POST", url)
                return
            length = int(self.headers.get("Content-Length") or 0)
            if length > PHONE_MEDIA_INDEX_MAX:
                raise ValueError("body too large")
            body = self.read_body()
            if url.path == "/api/phone/media/index":
                self.send_json(media_store_index(body))
            elif url.path == "/api/phone/media/request":
                self.send_json(media_request(body))
            elif url.path == "/api/phone/media/report":
                self.send_json(media_report(body))
            elif url.path == "/api/phone/media/release":
                self.send_json(media_release(body))
            elif url.path == "/api/inbox":
                self.send_json(inbox_post(body))
            elif url.path == "/api/inbox/read":
                self.send_json(inbox_read(body))
            elif url.path == "/api/inbox/drop":
                self.send_json(inbox_drop(body))
            elif url.path == "/api/volume":
                self.send_json(set_volume(body))
            elif url.path == "/api/lease":
                self.send_json(take_lease(body))
            elif url.path == "/api/lease/position":
                self.send_json(heartbeat(body))
            elif url.path == "/api/money/refresh":
                self.send_json(start_money_refresh())
            elif url.path == "/api/kill":
                self.send_json(kill_unit(body))
            elif url.path == "/api/gpu/free":
                self.send_json(gpu_free(body))
            elif url.path == "/api/phone/audit":
                self.send_json(phone_audit_store(body))
            elif url.path == "/api/phone/notify":
                self.send_json(phone_notify(body))
            elif url.path == "/api/phone/forward":
                self.send_json(forward_set(body))
            elif url.path == "/api/power":
                self.send_json(power(body))
            elif url.path == "/api/media":
                self.send_json(media_action(body))
            else:
                self.send_json({"error": "not found"}, 404)
        except ValueError as err:
            self.send_json({"error": str(err)}, 400)
        except (OSError, MpdError, subprocess.SubprocessError, http.client.HTTPException) as err:
            self.send_json({"error": str(err)}, 503)

    def do_PATCH(self):
        url = urllib.parse.urlparse(self.path)
        try:
            if not url.path.startswith("/api/watch/"):
                self.send_json({"error": "not found"}, 404)
                return
            self.proxy_watch("PATCH", url)
        except ValueError as err:
            self.send_json({"error": str(err)}, 400)
        except (OSError, http.client.HTTPException) as err:
            self.send_json({"error": str(err)}, 503)

    def do_DELETE(self):
        url = urllib.parse.urlparse(self.path)
        try:
            if not url.path.startswith("/api/watch/"):
                self.send_json({"error": "not found"}, 404)
                return
            self.proxy_watch("DELETE", url)
        except ValueError as err:
            self.send_json({"error": str(err)}, 400)
        except (OSError, http.client.HTTPException) as err:
            self.send_json({"error": str(err)}, 503)

    def receive_media(self, url) -> None:
        query = dict(urllib.parse.parse_qsl(url.query))
        try:
            length = int(self.headers.get("Content-Length") or 0)
            if url.path == "/api/phone/media/thumb":
                if length > PHONE_MEDIA_THUMB_MAX:
                    raise ValueError("thumbnail too large")
                self.send_json(media_receive_thumb(query.get("id") or "", self.rfile.read(length)))
            else:
                self.send_json(media_receive_file(query.get("id") or "", self.rfile, length, self.headers.get("X-Sha256") or ""))
        except ValueError as err:
            self.close_connection = True
            self.send_json({"error": str(err)}, 400)
        except OSError as err:
            self.close_connection = True
            self.send_json({"error": str(err)}, 503)


def main() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    inbox_load()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.daemon_threads = True
    print(f"phone-bridge listening on {HOST}:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
