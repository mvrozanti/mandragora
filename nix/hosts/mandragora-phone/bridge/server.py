from __future__ import annotations

import hashlib
import json
import os
import re
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
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
LRCLIB_GET = "https://lrclib.net/api/get"
USER_AGENT = "mandragora-phone-bridge/1 (+https://github.com/mvrozanti/mandragora)"
VERSION = 1
PORTS = {"mpd": MPD_PORT, "ytdl": 6685, "theme": 6684, "mympd": 6680, "bridge": PORT}
MUSIC_FOLDER_ID = "mandragora-music"
LEASE_FILE = STATE_DIR / "lease.json"
LRCLIB_MISS_TTL = 24 * 3600
AUDIO_SUFFIXES = {".mp3", ".m4a", ".flac", ".wav", ".ogg", ".opus", ".aac", ".wma"}

SINK_LINE = re.compile(r"^\s*│\s*(?P<default>\*)?\s*(?P<id>\d+)\.\s+(?P<name>.+?)\s+\[vol:\s*(?P<vol>[\d.]+)(?P<muted>\s+MUTED)?\]\s*$")
LRC_LINE = re.compile(r"^\[(\d+):(\d+(?:\.\d+)?)\](.*)$")

volume_lock = threading.Lock()
lease_lock = threading.Lock()
lrclib_slot = threading.Semaphore(1)
lrclib_misses: dict[str, float] = {}


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
    active = mpd_dict("status").get("state") in ("play", "pause")
    song_id = None
    if file:
        song_id = mpd_dict(f"playlistfind file {mpd_quote(file)}").get("Id")
        if song_id is None:
            song_id = mpd_dict(f"addid {mpd_quote(file)}").get("Id")
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


def lease_state() -> dict:
    with lease_lock:
        lease = read_lease()
        if lease.get("owner") == "phone":
            return lease
        try:
            now = mpd_now()
        except (OSError, MpdError, KeyError, ValueError):
            now = {}
        lease = {
            "owner": "desk",
            "file": now.get("file", lease.get("file")),
            "elapsed": now.get("elapsed", lease.get("elapsed", 0.0)),
            "playing": now.get("playing", False),
            "artist": now.get("artist"),
            "title": now.get("title"),
            "duration": now.get("duration"),
            "since": lease.get("since") or time.time(),
        }
        return lease


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
            lease = {
                "owner": "phone",
                "file": body.get("file") or now.get("file") or current.get("file"),
                "elapsed": float(body.get("elapsed", now.get("elapsed", current.get("elapsed", 0.0)))),
                "playing": bool(body.get("playing", now.get("playing", False))),
                "artist": now.get("artist", current.get("artist")),
                "title": now.get("title", current.get("title")),
                "duration": now.get("duration", current.get("duration")),
                "since": time.time(),
            }
        else:
            file = body.get("file") or current.get("file")
            elapsed = float(body.get("elapsed", current.get("elapsed", 0.0)))
            playing = bool(body.get("playing", current.get("playing", False)))
            mpd_resume(file, elapsed, playing)
            now = mpd_now()
            lease = {
                "owner": "desk",
                "file": now.get("file"),
                "elapsed": now.get("elapsed", elapsed),
                "playing": now.get("playing", playing),
                "artist": now.get("artist"),
                "title": now.get("title"),
                "duration": now.get("duration"),
                "since": time.time(),
            }
        write_lease(lease)
        return lease


def heartbeat(body: dict) -> dict:
    with lease_lock:
        lease = read_lease()
        if lease.get("owner") != "phone":
            raise ValueError("phone does not own playback")
        for key in ("file", "elapsed", "playing", "artist", "title", "duration"):
            if key in body:
                lease[key] = body[key]
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
        return None
    params = {"artist_name": tags["artist"], "track_name": tags["title"]}
    if tags.get("album"):
        params["album_name"] = tags["album"]
    if tags.get("duration"):
        params["duration"] = str(int(round(tags["duration"])))
    request = urllib.request.Request(LRCLIB_GET + "?" + urllib.parse.urlencode(params), headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            return json.load(response)
    except (urllib.error.URLError, ValueError, TimeoutError):
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
    synced_text = (found or {}).get("syncedLyrics")
    if synced_text and track.suffix.lower() in AUDIO_SUFFIXES:
        lrc_path.write_text(synced_text, encoding="utf-8")
        return {"synced": parse_lrc(synced_text), "plain": None, "source": "lrclib"}
    lrclib_misses[file] = time.time()
    plain = plain or (found or {}).get("plainLyrics") or None
    return {"synced": None, "plain": plain, "source": "cache" if record and record.get("lyrics") else ("lrclib:plain" if plain else "miss")}


def config() -> dict:
    return {
        "version": VERSION,
        "desktop": {"ip": desktop_ip(), "host": "mandragora-desktop"},
        "ports": PORTS,
        "music": {"folderId": MUSIC_FOLDER_ID, "dir": str(MUSIC_DIR)},
        "hub": load_json(SERVICES_JSON, {}),
        "time": time.time(),
    }


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

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = dict(urllib.parse.parse_qsl(url.query))
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
            elif url.path == "/api/lyrics":
                file = query.get("file")
                if not file:
                    self.send_json({"error": "file required"}, 400)
                else:
                    self.send_json(lyrics_for(file))
            else:
                self.send_json({"error": "not found"}, 404)
        except ValueError as err:
            self.send_json({"error": str(err)}, 400)
        except (OSError, MpdError, subprocess.SubprocessError) as err:
            self.send_json({"error": str(err)}, 503)

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        try:
            body = self.read_body()
            if url.path == "/api/volume":
                self.send_json(set_volume(body))
            elif url.path == "/api/lease":
                self.send_json(take_lease(body))
            elif url.path == "/api/lease/position":
                self.send_json(heartbeat(body))
            else:
                self.send_json({"error": "not found"}, 404)
        except ValueError as err:
            self.send_json({"error": str(err)}, 400)
        except (OSError, MpdError, subprocess.SubprocessError) as err:
            self.send_json({"error": str(err)}, 503)


def main() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.daemon_threads = True
    print(f"phone-bridge listening on {HOST}:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
