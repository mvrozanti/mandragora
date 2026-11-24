import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import cast

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import server

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16


class Players:
    def __init__(self, folder: Path):
        self.log = folder / "calls"
        self.output = folder / "output"
        self.output.write_text("")

    def __call__(self, *rows: tuple[str, ...]) -> None:
        self.output.write_text("".join("\t".join(row) + "\n" for row in rows))

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines() if self.log.exists() else []


@pytest.fixture
def playerctl(tmp_path, monkeypatch) -> Players:
    players = Players(tmp_path)
    script = tmp_path / "playerctl"
    script.write_text(f'#!/bin/sh\necho "$@" >> {players.log}\ncat {players.output}\n')
    script.chmod(0o755)
    monkeypatch.setattr(server, "PLAYERCTL", str(script))
    monkeypatch.setattr(server.time, "sleep", lambda seconds: None)
    return players


class SttServer(ThreadingHTTPServer):
    seen: list[tuple[str, bytes]]
    reply: tuple[int, dict]


class FakeStt(BaseHTTPRequestHandler):
    def do_GET(self):
        owner = cast(SttServer, self.server)
        owner.seen.append(("GET " + self.path, b""))
        data = json.dumps({"model_loaded": True, "gpu_lock_holder": None}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        owner = cast(SttServer, self.server)
        body = self.rfile.read(int(self.headers["Content-Length"]))
        owner.seen.append((self.headers["Content-Type"], body))
        status, payload = owner.reply
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        return


@pytest.fixture
def stt(monkeypatch):
    fake = SttServer(("127.0.0.1", 0), FakeStt)
    fake.seen = []
    fake.reply = (200, {"text": "  hello there  ", "language": "en", "duration": 1.5})
    threading.Thread(target=fake.serve_forever, daemon=True).start()
    monkeypatch.setattr(server, "STT_URL", f"http://127.0.0.1:{fake.server_port}/transcribe")
    yield fake
    fake.shutdown()


@pytest.fixture(autouse=True)
def forward(tmp_path, monkeypatch) -> Path:
    log = tmp_path / "forward-changed"
    monkeypatch.setattr(server, "FORWARD_FILE", tmp_path / "forward.json")
    monkeypatch.setattr(server, "FORWARD_CHANGED", ["sh", "-c", f"echo changed >> {log}"])
    return log


@pytest.fixture
def bridge():
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{httpd.server_port}"
    httpd.shutdown()


def fetch(url, data=None, headers=None):
    request = urllib.request.Request(url, data=data, headers=headers or {}, method="POST" if data is not None else "GET")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read())


def test_micros_to_seconds():
    assert server.micros_to_seconds("13567000012") == pytest.approx(13567.000012)
    assert server.micros_to_seconds("") == 0.0
    assert server.micros_to_seconds("abc") == 0.0


def test_media_art_path_accepts_only_small_local_images(tmp_path, monkeypatch):
    image = tmp_path / "cover.png"
    image.write_bytes(PNG)
    assert server.media_art_path(f"file://{image}") == image
    assert server.media_art_path(f"https://example.org/{image.name}") is None
    other = tmp_path / "notes.txt"
    other.write_text("x")
    assert server.media_art_path(f"file://{other}") is None
    assert server.media_art_path(f"file://{tmp_path}/missing.png") is None
    monkeypatch.setattr(server, "MEDIA_ART_MAX", 4)
    assert server.media_art_path(f"file://{image}") is None


def test_media_state_hides_mirrors_and_stopped_players(playerctl, tmp_path):
    art = tmp_path / "thumb.png"
    art.write_bytes(PNG)
    playerctl(
        ("mpd", "Playing", "song", "artist", "", "", "", ""),
        ("kdeconnect.mpris_phone", "Playing", "echo", "", "", "", "", ""),
        ("playerctld", "Playing", "proxy", "", "", "", "", ""),
        ("vlc.instance_9", "Stopped", "old", "", "", "", "", ""),
        ("mpv", "Paused", "clip", "", "file:///x.mkv", "5000000", "60000000", ""),
        ("firefox.instance_1_2", "Playing", "video", "chan", "https://www.youtube.com/watch?v=x", "1500000", "3000000", f"file://{art}"),
    )
    players = server.media_state()["players"]
    assert [p["player"] for p in players] == ["firefox.instance_1_2", "mpv"]
    video, clip = players
    assert video["source"] == "YouTube"
    assert video["position"] == pytest.approx(1.5)
    assert video["length"] == pytest.approx(3.0)
    assert video["art"] == "thumb.png"
    assert clip["source"] == "mpv"
    assert clip["art"] == ""


def test_media_action_validates_and_runs(playerctl):
    with pytest.raises(ValueError):
        server.media_action({"player": "firefox", "action": "rm"})
    with pytest.raises(ValueError):
        server.media_action({"player": "a; reboot", "action": "pause"})
    with pytest.raises(ValueError):
        server.media_action({"player": "firefox", "action": "seek"})
    server.media_action({"player": "firefox.instance_1_2", "action": "seek", "position": -3})
    server.media_action({"player": "firefox.instance_1_2", "action": "pause"})
    calls = playerctl.calls()
    assert "-p firefox.instance_1_2 position 0.000" in calls
    assert "-p firefox.instance_1_2 pause" in calls


def test_media_art_reads_the_players_image(playerctl, tmp_path):
    art = tmp_path / "a.png"
    art.write_bytes(PNG)
    (tmp_path / "output").write_text(f"file://{art}\n")
    assert server.media_art("firefox.instance_1_2") == (PNG, "image/png")
    assert server.media_art("kdeconnect.mpris_x") is None
    assert server.media_art("bad name") is None


def test_transcribe_forwards_audio_as_multipart(stt):
    result = server.transcribe_audio(b"AUDIO", "audio/mp4")
    assert (result["text"], result["language"], result["duration"], result["task"]) == ("hello there", "en", 1.5, "transcribe")
    content_type, body = stt.seen[0]
    assert content_type.startswith("multipart/form-data; boundary=")
    assert b'name="audio"; filename="speech.m4a"' in body
    assert b"\r\n\r\nAUDIO\r\n" in body
    assert b'name="task"\r\n\r\ntranscribe\r\n' in body
    assert b'name="language"' not in body


def test_transcribe_passes_task_and_language_and_refuses_odd_ones(stt):
    server.transcribe_audio(b"AUDIO", "audio/mp4", "translate", "pt")
    _, body = stt.seen[0]
    assert b'name="task"\r\n\r\ntranslate\r\n' in body
    assert b'name="language"\r\n\r\npt\r\n' in body
    with pytest.raises(ValueError, match="task"):
        server.transcribe_audio(b"AUDIO", "audio/mp4", "summarize")
    with pytest.raises(ValueError, match="language"):
        server.transcribe_audio(b"AUDIO", "audio/mp4", "transcribe", "pt\r\nx")


def test_transcribe_reports_why_it_failed(stt, monkeypatch):
    with pytest.raises(ValueError):
        server.transcribe_audio(b"", "audio/mp4")
    stt.reply = (503, {"detail": "gpu busy: ollama"})
    with pytest.raises(OSError, match="gpu busy: ollama"):
        server.transcribe_audio(b"AUDIO", "audio/mp4")
    monkeypatch.setattr(server, "STT_URL", "http://127.0.0.1:9/transcribe")
    with pytest.raises(OSError, match="not running"):
        server.transcribe_audio(b"AUDIO", "audio/mp4")


def test_paths_never_leave_the_music_folder(tmp_path, monkeypatch):
    (tmp_path / "a").mkdir()
    song = tmp_path / "a" / "s.mp3"
    song.write_bytes(b"x")
    (tmp_path / "a" / "notes.txt").write_text("x")
    monkeypatch.setattr(server, "MUSIC_DIR", tmp_path)
    assert server.music_path("a/s.mp3") == song
    for bad in ("../etc/passwd", "a/notes.txt", "a/missing.mp3", "/etc/hostname"):
        with pytest.raises(ValueError):
            server.music_path(bad)
    assert server.safe_track("a/s.mp3") == song
    assert server.safe_track("../outside.mp3") is None


def test_the_music_index_lists_what_the_phone_mirrors(bridge, tmp_path, monkeypatch):
    for rel, data in (("b/two.flac", b"22"), ("a/one.mp3", b"1"), ("a/one.lrc", b"[00:01]x"), ("a/cover.jpg", b"j"), ("a/.one.mp3.part", b"p"), (".viz/stem.mp3", b"v"), (".lyrics/x.lrc", b"l")):
        (tmp_path / rel).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / rel).write_bytes(data)
    os.utime(tmp_path / "a" / "one.mp3", (1700000000, 1700000000))
    (tmp_path / "a" / "elsewhere.mp3").symlink_to(tmp_path / "b" / "two.flac")
    monkeypatch.setattr(server, "MUSIC_DIR", tmp_path)
    status, body = fetch(f"{bridge}/api/music/index")
    assert status == 200
    assert [row[:2] for row in body["files"]] == [["a/one.lrc", 8], ["a/one.mp3", 1], ["b/two.flac", 2]]
    assert body["files"][1][2] == 1700000000
    status, again = fetch(f"{bridge}/api/music/index?have={body['version']}")
    assert again == {"version": body["version"], "unchanged": True}
    (tmp_path / "b" / "two.flac").write_bytes(b"333")
    status, changed = fetch(f"{bridge}/api/music/index?have={body['version']}")
    assert changed["version"] != body["version"] and changed["files"][2][:2] == ["b/two.flac", 3]
    assert server.music_path("a/one.lrc") == tmp_path / "a" / "one.lrc"


def test_the_kill_list_never_offers_the_session_core():
    for unit in ("phone-bridge.service", "pipewire.service", "dbus.socket", "app-hyprland-1.scope", "session.slice/x"):
        assert server.protected_unit(unit)
    assert not server.protected_unit("app-firefox-123.scope")


def test_unit_names_read_as_people_would():
    assert server.unit_kind("tmux-spawn-abc.scope") == "tmux pane"
    assert server.unit_kind("kitty-12.scope") == "kitty window"
    assert server.unit_kind("mpd.service") == "service"
    assert server.unit_kind("app-firefox-1.scope") == "app"
    assert server.unit_kind("run-u5.scope") == "scope"
    assert server.unit_title("app-org.mozilla.firefox-123.scope") == "firefox"
    assert server.unit_title("mpd.service") == "mpd"


def test_lyrics_and_quoting():
    assert server.parse_lrc("[00:01.50] one\nnoise\n[1:02]two") == [{"t": 1.5, "x": "one"}, {"t": 62.0, "x": "two"}]
    assert server.mpd_quote('a "b" \\c') == '"a \\"b\\" \\\\c"'
    assert server.sniff_image(b"\xff\xd8rest") == "image/jpeg"
    assert server.sniff_image(PNG) == "image/png"
    assert server.sniff_image(b"RIFF\x00\x00\x00\x00WEBPxx") == "image/webp"
    assert server.sniff_image(b"??") == "application/octet-stream"


def test_a_phone_lease_lapses_without_heartbeats(monkeypatch):
    monkeypatch.setattr(server.time, "time", lambda: 1000.0)
    assert server.phone_lease_live({"owner": "phone", "heartbeat": 1000 - server.PHONE_LEASE_TTL + 1}, None)
    assert not server.phone_lease_live({"owner": "phone", "heartbeat": 1000 - server.PHONE_LEASE_TTL - 1}, None)
    assert not server.phone_lease_live({"owner": "desk", "heartbeat": 1000}, None)
    assert not server.phone_lease_live({"owner": "phone", "heartbeat": 1000}, {"playing": True})


def test_only_the_device_that_took_the_music_moves_the_lease(monkeypatch, tmp_path):
    monkeypatch.setattr(server, "LEASE_FILE", tmp_path / "lease.json")
    monkeypatch.setattr(server, "STATE_DIR", tmp_path)
    monkeypatch.setattr(server, "mpd_now", lambda: {"file": "desk.mp3", "elapsed": 5.0, "playing": False})
    monkeypatch.setattr(server, "safe_now", lambda: {"file": "desk.mp3", "elapsed": 5.0, "playing": False})
    tags = {"title": "t", "artist": "a", "duration": 100.0}
    taken = server.take_lease({"owner": "phone", "file": "mine.mp3", "elapsed": 1.0, "device": "phone-a", **tags})
    assert taken["device"] == "phone-a"
    stray = server.heartbeat({"file": "stray.mp3", "elapsed": 2504.8, "playing": False, "device": "emulator", **tags})
    assert (stray["file"], stray["elapsed"]) == ("mine.mp3", 1.0)
    assert server.heartbeat({"file": "old-build.mp3", "elapsed": 3.0, **tags})["file"] == "mine.mp3"
    moved = server.heartbeat({"file": "next.mp3", "elapsed": 7.0, "playing": True, "device": "phone-a", **tags})
    assert (moved["file"], moved["elapsed"], moved["device"]) == ("next.mp3", 7.0, "phone-a")
    assert server.read_lease()["file"] == "next.mp3"


def test_a_lease_from_before_devices_goes_to_the_first_device_that_beats(monkeypatch, tmp_path):
    monkeypatch.setattr(server, "LEASE_FILE", tmp_path / "lease.json")
    monkeypatch.setattr(server, "STATE_DIR", tmp_path)
    monkeypatch.setattr(server, "safe_now", lambda: {"file": "desk.mp3", "elapsed": 5.0, "playing": False})
    tags = {"title": "t", "artist": "a", "duration": 100.0}
    server.write_lease({"owner": "phone", "file": "mine.mp3", "elapsed": 1.0, "playing": False, "since": 1.0})
    assert server.heartbeat({"file": "mine.mp3", "elapsed": 2.0, "device": "phone-a", **tags})["device"] == "phone-a"
    assert server.heartbeat({"file": "stray.mp3", "elapsed": 9.0, "device": "emulator", **tags})["file"] == "mine.mp3"


def test_http_media_and_transcribe(bridge, playerctl, stt):
    playerctl(("firefox.instance_1_2", "Playing", "video", "", "https://youtu.be/x", "", "", ""))
    status, body = fetch(f"{bridge}/api/media")
    assert status == 200
    assert body["players"][0]["source"] == "YouTube"
    status, body = fetch(f"{bridge}/api/media", json.dumps({"player": "x", "action": "nope"}).encode(), {"Content-Type": "application/json"})
    assert status == 400
    status, body = fetch(f"{bridge}/api/transcribe", b"AUDIO", {"Content-Type": "audio/mp4"})
    assert (status, body["text"]) == (200, "hello there")
    stt.reply = (503, {"detail": "gpu busy: x"})
    status, body = fetch(f"{bridge}/api/transcribe", b"AUDIO", {"Content-Type": "audio/mp4"})
    assert (status, body["error"]) == (503, "gpu busy: x")
    status, _ = fetch(f"{bridge}/api/nothing-here")
    assert status == 404


def test_http_refuses_oversized_audio(bridge, monkeypatch):
    monkeypatch.setattr(server, "STT_MAX", 3)
    status, body = fetch(f"{bridge}/api/transcribe", b"AUDIO", {"Content-Type": "audio/mp4"})
    assert (status, body["error"]) == (400, "audio too long")


JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 32
PHOTO = b"car photo bytes" * 100
PHOTO_SHA = server.hashlib.sha256(PHOTO).hexdigest()


@pytest.fixture
def media_dir(tmp_path, monkeypatch):
    folder = tmp_path / "phone-media"
    monkeypatch.setattr(server, "PHONE_MEDIA_DIR", folder)
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "127.0.0.1")
    return folder


def post_json(url, payload):
    return fetch(url, json.dumps(payload).encode(), {"Content-Type": "application/json"})


def index(bridge, *ids):
    items = [{"id": i, "name": f"{i}.jpg", "path": "DCIM/Camera/", "kind": "image", "mime": "image/jpeg", "size": len(PHOTO), "taken": 1, "junk": "x"} for i in ids]
    return post_json(f"{bridge}/api/phone/media/index", {"items": items})


def upload(bridge, mid, data, sha):
    return fetch(f"{bridge}/api/phone/media/file?id={mid}", data, {"Content-Type": "application/octet-stream", "X-Sha256": sha})


def test_media_ids_are_digits_only():
    assert server.media_ids(["1", 2, "1"]) == ["1", "2"]
    assert server.media_ids(None) == []
    for bad in (["../x"], ["1;rm"], "12", [""]):
        with pytest.raises(ValueError):
            server.media_ids(bad)


def test_phone_media_moves_a_photo_end_to_end(bridge, media_dir):
    status, jobs = index(bridge, "7", "8")
    assert (status, jobs) == (200, {"thumbs": [], "pull": [], "remove": [], "reindex": False})
    assert "junk" not in server.media_index_items()["7"]

    status, body = post_json(f"{bridge}/api/phone/media/request", {"thumbs": ["7"], "pull": ["7"]})
    assert status == 200
    assert body["jobs"]["thumbs"] == ["7"] and body["jobs"]["pull"] == ["7"]
    status, jobs = fetch(f"{bridge}/api/phone/media/jobs")
    assert jobs == {"thumbs": ["7"], "pull": ["7"], "remove": [], "reindex": False}

    status, _ = fetch(f"{bridge}/api/phone/media/thumb?id=7", b"not a jpeg", {"Content-Type": "image/jpeg"})
    assert status == 400
    status, _ = fetch(f"{bridge}/api/phone/media/thumb?id=7", JPEG, {"Content-Type": "image/jpeg"})
    assert status == 200
    with urllib.request.urlopen(f"{bridge}/api/phone/media/thumb?id=7") as response:
        assert response.read() == JPEG

    status, body = post_json(f"{bridge}/api/phone/media/request", {"remove": ["7"]})
    assert status == 400 and "not held" in body["error"]

    status, _ = upload(bridge, "7", PHOTO, "0" * 64)
    assert status == 400
    assert not (media_dir / "held" / "7").exists()
    status, body = upload(bridge, "7", PHOTO, PHOTO_SHA)
    assert (status, body["sha256"]) == (200, PHOTO_SHA)
    with urllib.request.urlopen(f"{bridge}/api/phone/media/held?id=7") as response:
        assert response.read() == PHOTO

    status, body = post_json(f"{bridge}/api/phone/media/request", {"remove": ["7"], "pull": ["7"]})
    assert body["jobs"] == {"thumbs": [], "pull": [], "remove": {"7": PHOTO_SHA}}
    assert body["held"][0]["name"] == "7.jpg"
    status, jobs = fetch(f"{bridge}/api/phone/media/jobs")
    assert jobs["remove"] == [{"id": "7", "sha256": PHOTO_SHA}]

    status, body = post_json(f"{bridge}/api/phone/media/release", {"ids": ["7"]})
    assert body["released"] == []
    status, _ = post_json(f"{bridge}/api/phone/media/report", {"id": "7", "job": "remove"})
    assert status == 200
    log = [json.loads(line) for line in (media_dir / "removed.jsonl").read_text().splitlines()]
    assert [(e["id"], e["outcome"], e["name"]) for e in log] == [("7", "removed", "7.jpg")]
    status, body = post_json(f"{bridge}/api/phone/media/release", {"ids": ["7"]})
    assert body["released"] == ["7"]
    status, body = fetch(f"{bridge}/api/phone/media")
    assert body["held"] == [] and body["seen"] is not None and body["thumbs"] == ["7"]


def test_phone_media_failures_stop_retries_and_gone_items_leave_the_queue(bridge, media_dir):
    index(bridge, "1", "2", "3")
    post_json(f"{bridge}/api/phone/media/request", {"pull": ["1", "2"], "thumbs": ["3"]})
    status, _ = post_json(f"{bridge}/api/phone/media/report", {"id": "1", "job": "pull", "error": "permission denied"})
    assert status == 200
    status, body = fetch(f"{bridge}/api/phone/media")
    assert body["jobs"]["pull"] == ["2"]
    assert body["failed"]["1"]["error"] == "permission denied"
    status, _ = post_json(f"{bridge}/api/phone/media/report", {"id": "1", "job": "nope"})
    assert status == 400

    upload(bridge, "2", PHOTO, PHOTO_SHA)
    post_json(f"{bridge}/api/phone/media/request", {"remove": ["2"]})
    status, jobs = index(bridge, "1")
    assert jobs == {"thumbs": [], "pull": [], "remove": [], "reindex": False}
    log = [json.loads(line) for line in (media_dir / "removed.jsonl").read_text().splitlines()]
    assert [(e["id"], e["outcome"]) for e in log] == [("2", "gone")]

    status, _ = post_json(f"{bridge}/api/phone/media/index", {"items": "nope"})
    assert status == 400
    status, _ = fetch(f"{bridge}/api/phone/media/thumb?id=99")
    assert status == 404
    status, _ = fetch(f"{bridge}/api/phone/media/held?id=99")
    assert status == 404
    status, _ = fetch(f"{bridge}/api/phone/media/held?id=../x")
    assert status == 400


def test_phone_media_removes_what_the_desktop_archived(bridge, media_dir):
    index(bridge, "5")
    status, body = post_json(f"{bridge}/api/phone/media/request", {"archived": {"5": "nope"}})
    assert status == 400
    status, body = post_json(f"{bridge}/api/phone/media/request", {"archived": {"../5": PHOTO_SHA}})
    assert status == 400
    status, body = post_json(f"{bridge}/api/phone/media/request", {"archived": {"5": PHOTO_SHA}})
    assert status == 200 and body["jobs"]["remove"] == {"5": PHOTO_SHA}
    status, jobs = fetch(f"{bridge}/api/phone/media/jobs")
    assert jobs["remove"] == [{"id": "5", "sha256": PHOTO_SHA}]


def test_only_the_phone_sends_media(bridge, media_dir, monkeypatch):
    status, jobs = fetch(f"{bridge}/api/phone/media/jobs")
    assert (status, jobs["reindex"]) == (200, True)
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "100.64.0.9")
    for path in ("index", "report"):
        status, body = post_json(f"{bridge}/api/phone/media/{path}", {"items": []})
        assert (status, body["error"]) == (403, "only the phone sends its media")
    status, _ = fetch(f"{bridge}/api/phone/media/jobs")
    assert status == 403
    status, _ = upload(bridge, "7", PHOTO, PHOTO_SHA)
    assert status == 403
    status, _ = fetch(f"{bridge}/api/phone/media")
    assert status == 200
    status, _ = post_json(f"{bridge}/api/phone/media/request", {"thumbs": []})
    assert status == 200


def test_media_peers_default_to_the_phone_on_the_tailnet(tmp_path, monkeypatch):
    tailnet = tmp_path / "tailnet.json"
    tailnet.write_text(json.dumps({"phone": {"ip": "100.64.0.5"}}))
    monkeypatch.setattr(server, "TAILNET_JSON", str(tailnet))
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", None)
    assert server.media_peers() == {"100.64.0.5"}
    assert server.media_from_phone("/api/phone/media/thumb", "GET", "127.0.0.1")
    assert not server.media_from_phone("/api/phone/media/thumb", "POST", "127.0.0.1")
    assert server.media_from_phone("/api/phone/media/index", "POST", "100.64.0.5")


def test_stt_proxy_passes_only_status_and_warmup(bridge, stt, monkeypatch):
    monkeypatch.setattr(server, "STT_BASE", f"http://127.0.0.1:{stt.server_port}")
    status, body = fetch(f"{bridge}/api/stt/status")
    assert (status, body["model_loaded"]) == (200, True)
    assert stt.seen[-1][0] == "GET /status"
    status, _ = fetch(f"{bridge}/api/stt/warmup", b"")
    assert status == 200
    status, body = fetch(f"{bridge}/api/stt/transcribe", b"AUDIO", {"Content-Type": "audio/mp4"})
    assert status == 400
    status, _ = fetch(f"{bridge}/api/stt/../etc")
    assert status == 400
    monkeypatch.setattr(server, "STT_BASE", "http://127.0.0.1:9")
    status, body = fetch(f"{bridge}/api/stt/status")
    assert (status, body["error"]) == (503, "speech-to-text is not running on the desktop")


def test_transcribe_route_reads_task_and_language(bridge, stt):
    status, body = fetch(f"{bridge}/api/transcribe?task=translate&language=pt", b"AUDIO", {"Content-Type": "audio/mp4"})
    assert (status, body["task"]) == (200, "translate")
    status, body = fetch(f"{bridge}/api/transcribe?task=nope", b"AUDIO", {"Content-Type": "audio/mp4"})
    assert status == 400


@pytest.fixture
def inbox(tmp_path, monkeypatch):
    monkeypatch.setattr(server, "INBOX_FILE", tmp_path / "inbox.json")
    monkeypatch.setattr(server, "inbox_data", {"items": [], "next": 1, "read": 0})
    return tmp_path / "inbox.json"


def test_inbox_keeps_reads_and_drops_items(bridge, inbox):
    status, body = post_json(f"{bridge}/api/inbox", {"source": "watch", "title": "fired", "text": "a thing happened", "level": "alert", "ref": {"event": 7}})
    assert (status, body["id"]) == (200, 1)
    post_json(f"{bridge}/api/inbox", {"text": "plain note"})
    status, view = fetch(f"{bridge}/api/inbox?after=0")
    assert [item["id"] for item in view["items"]] == [1, 2]
    assert view["items"][0]["level"] == "alert" and view["items"][1]["title"] == "mandragora"
    assert json.loads(inbox.read_text())["next"] == 3
    status, body = post_json(f"{bridge}/api/inbox/read", {"upTo": 99})
    assert body["read"] == 2
    status, body = post_json(f"{bridge}/api/inbox/drop", {"id": 1})
    assert body["left"] == 1
    status, body = post_json(f"{bridge}/api/inbox/drop", {"upTo": 2})
    assert body["left"] == 0
    server.inbox_data.update({"items": [], "next": 1, "read": 0})
    server.inbox_load()
    assert server.inbox_data["next"] == 3 and server.inbox_data["read"] == 2


def test_inbox_refuses_bad_posts_and_long_polls_until_something_arrives(bridge, inbox):
    assert post_json(f"{bridge}/api/inbox", {"text": "  "})[0] == 400
    assert post_json(f"{bridge}/api/inbox", {"text": "x", "level": "loud"})[0] == 400
    assert post_json(f"{bridge}/api/inbox", {"text": "x", "ref": {"big": "y" * 600}})[0] == 400
    started = time.monotonic()
    threading.Timer(0.3, lambda: server.inbox_post({"text": "late"})).start()
    status, view = fetch(f"{bridge}/api/inbox?after=0&wait=5")
    assert status == 200 and view["items"][0]["text"] == "late"
    assert time.monotonic() - started < 4


def test_inbox_long_poll_wakes_when_a_new_build_is_published(bridge, inbox, tmp_path, monkeypatch):
    meta = tmp_path / "app.json"
    monkeypatch.setattr(server, "APP_META", meta)
    monkeypatch.setattr(server, "INBOX_SLICE", 0.1)
    monkeypatch.setattr(server, "app_seen", {"mtime": None, "code": 0})
    meta.write_text(json.dumps({"versionCode": 5}))
    status, view = fetch(f"{bridge}/api/inbox?after=0")
    assert (status, view["app"]) == (200, 5)
    started = time.monotonic()
    threading.Timer(0.3, lambda: meta.write_text(json.dumps({"versionCode": 6}))).start()
    status, view = fetch(f"{bridge}/api/inbox?after=0&wait=5&app=5")
    assert (status, view["app"], view["items"]) == (200, 6, [])
    assert time.monotonic() - started < 3
    started = time.monotonic()
    status, view = fetch(f"{bridge}/api/inbox?after=0&wait=1&app=6")
    assert view["app"] == 6 and time.monotonic() - started >= 0.9


def test_inbox_long_poll_wakes_when_phone_notifications_are_switched(bridge, inbox, monkeypatch):
    monkeypatch.setattr(server, "INBOX_SLICE", 0.1)
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "127.0.0.1")
    status, view = fetch(f"{bridge}/api/inbox?after=0")
    assert (status, view["forward"]) == (200, True)
    started = time.monotonic()
    threading.Timer(0.3, lambda: server.FORWARD_FILE.write_text(json.dumps({"on": False}))).start()
    status, view = fetch(f"{bridge}/api/inbox?after=0&wait=5&forward=1")
    assert (status, view["forward"], view["items"]) == (200, False, [])
    assert time.monotonic() - started < 3
    monkeypatch.setattr(server, "INBOX_SLICE", 30.0)
    started = time.monotonic()
    threading.Timer(0.3, lambda: server.forward_set({"on": True})).start()
    status, view = fetch(f"{bridge}/api/inbox?after=0&wait=5&forward=0")
    assert view["forward"] is True and time.monotonic() - started < 3
    started = time.monotonic()
    status, view = fetch(f"{bridge}/api/inbox?after=0&wait=1&forward=1")
    assert view["forward"] is True and time.monotonic() - started >= 0.9


def test_watch_proxy_only_forwards_watchs_api(bridge):
    status, body = fetch(f"{bridge}/api/watch/admin/secrets")
    assert (status, body["error"]) == (400, "only watch's api is proxied")
    status, _ = fetch(f"{bridge}/api/watch/api/../../etc")
    assert status == 400
def test_an_empty_file_is_still_a_file(bridge, media_dir):
    index(bridge, "3")
    empty = server.hashlib.sha256(b"").hexdigest()
    status, body = upload(bridge, "3", b"", empty)
    assert (status, body["sha256"]) == (200, empty)
    assert (media_dir / "held" / "3").read_bytes() == b""


@pytest.fixture
def systemctl(tmp_path, monkeypatch):
    log = tmp_path / "systemctl-calls"
    script = tmp_path / "systemctl"
    script.write_text(f'#!/bin/sh\necho "$@" >> {log}\n[ "$1" = poweroff ] && {{ echo "inhibited by backup" >&2; exit 1; }}\nexit 0\n')
    script.chmod(0o755)
    uptime = tmp_path / "uptime"
    uptime.write_text("93784.52 1000.00\n")
    monkeypatch.setattr(server, "SYSTEMCTL", str(script))
    monkeypatch.setattr(server, "UPTIME_FILE", str(uptime))
    monkeypatch.setattr(server, "SWITCH_LOCK", str(tmp_path / "switch.lock"))
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "127.0.0.1")
    return log


def test_power_reboots_through_systemctl_and_reports_failures(bridge, systemctl):
    status, body = fetch(f"{bridge}/api/power")
    assert (status, body) == (200, {"uptime": 93784.52, "switching": False})
    status, body = post_json(f"{bridge}/api/power", {"action": "reboot"})
    assert (status, body) == (200, {"action": "reboot"})
    status, body = post_json(f"{bridge}/api/power", {"action": "poweroff"})
    assert (status, body["error"]) == (503, "inhibited by backup")
    status, body = post_json(f"{bridge}/api/power", {"action": "suspend"})
    assert status == 400
    assert systemctl.read_text().splitlines() == ["reboot", "poweroff"]


def test_power_waits_for_a_running_switch(bridge, systemctl):
    import fcntl

    with open(server.SWITCH_LOCK, "w") as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        status, body = fetch(f"{bridge}/api/power")
        assert body["switching"] is True
        status, body = post_json(f"{bridge}/api/power", {"action": "reboot"})
        assert (status, body["error"]) == (400, "a switch is running; try again when it ends")
    assert not systemctl.exists()


def test_only_the_phone_powers_the_desktop(bridge, systemctl, monkeypatch):
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "100.64.0.9")
    status, body = post_json(f"{bridge}/api/power", {"action": "reboot"})
    assert (status, body["error"]) == (403, "only the phone may power the desktop off")
    status, _ = fetch(f"{bridge}/api/power")
    assert status == 200
    assert not systemctl.exists()


SMI_XML = """<?xml version="1.0" ?>
<nvidia_smi_log>
  <gpu id="00000000:01:00.0">
    <product_name>NVIDIA GeForce RTX 5070 Ti</product_name>
    <fb_memory_usage><total>16303 MiB</total><used>10585 MiB</used></fb_memory_usage>
    <utilization><gpu_util>42 %</gpu_util></utilization>
    <temperature><gpu_temp>55 C</gpu_temp></temperature>
    <gpu_power_readings><instant_power_draw>106.05 W</instant_power_draw></gpu_power_readings>
    <processes>
      <process_info><pid>12384</pid><type>G</type><process_name>/etc/profiles/per-user/m/bin/firefox</process_name><used_memory>109 MiB</used_memory></process_info>
      <process_info><pid>13135</pid><type>C+G</type><process_name>/nix/store/x-firefox/lib/firefox/firefox -contentproc -appDir x</process_name><used_memory>324 MiB</used_memory></process_info>
      <process_info><pid>3298250</pid><type>C+G</type><process_name>S:\\steamapps\\common\\ForzaHorizon6\\forzahorizon6.exe</process_name><used_memory>8501 MiB</used_memory></process_info>
      <process_info><pid>777</pid><type>C</type><process_name>/nix/store/y-python3/bin/python3</process_name><used_memory>3900 MiB</used_memory></process_info>
      <process_info><pid>x</pid><type>G</type><process_name>broken</process_name><used_memory>N/A</used_memory></process_info>
    </processes>
  </gpu>
</nvidia_smi_log>
"""


class LocalServer(ThreadingHTTPServer):
    seen: list[tuple[str, dict]]
    replies: dict[str, tuple[int, dict]]


class FakeLocal(BaseHTTPRequestHandler):
    def answer(self, status: int, payload: dict) -> None:
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        owner = cast(LocalServer, self.server)
        self.answer(*owner.replies.get("GET " + self.path, (404, {"error": "nope"})))

    def do_POST(self):
        owner = cast(LocalServer, self.server)
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        owner.seen.append((self.path, json.loads(raw) if raw else {}))
        self.answer(*owner.replies.get("POST " + self.path, (404, {"error": "nope"})))

    def log_message(self, format, *args):
        return


@pytest.fixture
def gpu_desk(tmp_path, monkeypatch):
    xml = tmp_path / "smi.xml"
    xml.write_text(SMI_XML)
    smi = tmp_path / "nvidia-smi"
    smi.write_text(f"#!/bin/sh\ncat {xml}\n")
    smi.chmod(0o755)
    lock_json = tmp_path / "lock.json"
    lock_json.write_text(json.dumps({"holder": None, "unmanaged": {"pid": 3298250, "name": "forzahorizon6.exe (unmanaged)", "since": 5.0, "expected_seconds": None}}))
    lock = tmp_path / "gpu-lock"
    lock.write_text(f"#!/bin/sh\n[ \"$1 $2\" = 'status --json' ] && cat {lock_json}\n")
    lock.chmod(0o755)
    fake = LocalServer(("127.0.0.1", 0), FakeLocal)
    fake.seen = []
    fake.replies = {
        "GET /api/ps": (200, {"models": [{"name": "qwen3:8b", "size_vram": 5_000_000_000}, {"name": "on-cpu", "size_vram": 0}]}),
        "GET /status": (200, {"model_loaded": True, "config": {"model": "large-v3"}}),
        "POST /api/generate": (200, {"done": True, "done_reason": "unload"}),
        "POST /release": (200, {"ok": True}),
    }
    threading.Thread(target=fake.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{fake.server_port}"
    monkeypatch.setattr(server, "NVIDIA_SMI", str(smi))
    monkeypatch.setattr(server, "GPU_LOCK", str(lock))
    monkeypatch.setattr(server, "OLLAMA_URL", base)
    monkeypatch.setattr(server, "STT_BASE", base)
    monkeypatch.setattr(server, "pid_unit", lambda pid: "stt-core.service" if pid == 777 else "")
    yield fake
    fake.shutdown()


def test_gpu_state_merges_processes_and_names_who_is_outside_the_lock(bridge, gpu_desk):
    status, body = fetch(f"{bridge}/api/gpu")
    assert status == 200
    assert body["gpu"]["name"] == "NVIDIA GeForce RTX 5070 Ti"
    assert body["gpu"]["memTotal"] == 16303 * 1024 * 1024
    assert body["gpu"]["util"] == 42.0
    assert body["gpu"]["power"] == pytest.approx(106.05)
    names = [row["name"] for row in body["procs"]]
    assert names == ["forzahorizon6.exe", "python3", "firefox"]
    firefox = next(row for row in body["procs"] if row["name"] == "firefox")
    assert (firefox["mem"], firefox["kind"], firefox["pid"]) == (433 * 1024 * 1024, "compute", 13135)
    game = body["procs"][0]
    assert (game["outside"], game["holder"]) == (True, False)
    assert body["lock"]["holder"] is None
    assert body["lock"]["unmanaged"]["name"] == "forzahorizon6.exe"
    assert body["residents"] == [
        {"kind": "ollama", "name": "qwen3:8b", "mem": 5_000_000_000},
        {"kind": "stt", "name": "stt-core · large-v3", "mem": 3900 * 1024 * 1024},
    ]


def test_gpu_state_survives_a_desk_without_any_gpu_tool(bridge, tmp_path, monkeypatch):
    monkeypatch.setattr(server, "NVIDIA_SMI", str(tmp_path / "missing"))
    monkeypatch.setattr(server, "GPU_LOCK", str(tmp_path / "missing"))
    monkeypatch.setattr(server, "OLLAMA_URL", "http://127.0.0.1:9")
    monkeypatch.setattr(server, "STT_BASE", "http://127.0.0.1:9")
    status, body = fetch(f"{bridge}/api/gpu")
    assert status == 200
    assert (body["gpu"], body["procs"], body["residents"]) == (None, [], [])
    assert body["lock"]["error"] == "gpu-lock did not answer"


def test_gpu_free_asks_ollama_and_stt_core_to_let_go(bridge, gpu_desk):
    status, body = post_json(f"{bridge}/api/gpu/free", {"what": "ollama", "name": "qwen3:8b"})
    assert (status, body) == (200, {"freed": "qwen3:8b"})
    status, body = post_json(f"{bridge}/api/gpu/free", {"what": "stt"})
    assert (status, body) == (200, {"freed": "stt-core"})
    assert gpu_desk.seen == [("/api/generate", {"model": "qwen3:8b", "keep_alive": 0}), ("/release", {})]


def test_gpu_free_refuses_what_is_not_in_vram(bridge, gpu_desk):
    status, body = post_json(f"{bridge}/api/gpu/free", {"what": "ollama", "name": "on-cpu"})
    assert (status, body["error"]) == (400, "on-cpu is not in VRAM")
    status, body = post_json(f"{bridge}/api/gpu/free", {"what": "forzahorizon6.exe"})
    assert (status, body["error"]) == (400, "what must be ollama or stt")
    del gpu_desk.replies["POST /release"]
    status, body = post_json(f"{bridge}/api/gpu/free", {"what": "stt"})
    assert (status, body["error"]) == (503, "stt-core cannot release its model (HTTP 404)")
    assert gpu_desk.seen == [("/release", {})]


def test_config_carries_the_apps_the_phone_must_run(bridge, tmp_path, monkeypatch):
    identity = tmp_path / "identity.json"
    identity.write_text(json.dumps({"apps": [{"package": "com.tailscale.ipn", "name": "Tailscale", "unrestricted": True}, {"package": "md.obsidian"}, {"name": "no package"}]}))
    monkeypatch.setattr(server, "IDENTITY_JSON", str(identity))
    status, body = fetch(f"{bridge}/api/config")
    assert status == 200
    assert body["phone"] == {"apps": [
        {"package": "com.tailscale.ipn", "name": "Tailscale", "unrestricted": True},
        {"package": "md.obsidian", "name": "md.obsidian", "unrestricted": False},
    ]}


def test_phone_audit_is_kept_and_read_back(bridge, tmp_path, monkeypatch):
    monkeypatch.setattr(server, "STATE_DIR", tmp_path)
    monkeypatch.setattr(server, "PHONE_AUDIT_FILE", tmp_path / "phone-audit.json")
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "127.0.0.1")
    status, body = fetch(f"{bridge}/api/phone/audit")
    assert (status, body["checks"], body["ts"]) == (200, [], None)
    checks = [
        {"id": "battery:com.tailscale.ipn", "label": "Tailscale runs unrestricted", "ok": False, "detail": "battery optimised"},
        {"id": "always-on", "label": "Tailscale is the always-on VPN", "ok": None},
        {"id": "all-files", "label": "the desktop reaches photos", "ok": True, "extra": "dropped"},
    ]
    status, body = post_json(f"{bridge}/api/phone/audit", {"versionCode": 41, "checks": checks})
    assert (status, body) == (200, {"stored": 3})
    status, body = fetch(f"{bridge}/api/phone/audit")
    assert body["versionCode"] == 41
    assert body["failing"] == ["battery:com.tailscale.ipn"]
    assert body["checks"][2] == {"id": "all-files", "label": "the desktop reaches photos", "ok": True, "detail": ""}
    assert 0 <= body["age"] < 60
    status, body = post_json(f"{bridge}/api/phone/audit", {"checks": [{"label": "no id"}]})
    assert (status, body["error"]) == (400, "every check needs an id")


def test_only_the_phone_reports_on_itself(bridge, tmp_path, monkeypatch):
    monkeypatch.setattr(server, "PHONE_AUDIT_FILE", tmp_path / "phone-audit.json")
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "100.64.0.9")
    status, body = post_json(f"{bridge}/api/phone/audit", {"checks": []})
    assert (status, body["error"]) == (403, "only the phone reports on itself")
    assert not (tmp_path / "phone-audit.json").exists()


@pytest.fixture
def desktop(tmp_path, monkeypatch):
    proc = tmp_path / "proc"
    proc.mkdir()
    log = tmp_path / "notified"
    script = tmp_path / "notify-send"
    script.write_text(f'#!/bin/sh\nprintf "%s|" "$@" >> {log}\necho >> {log}\n')
    script.chmod(0o755)
    monkeypatch.setattr(server, "PROC_ROOT", proc)
    monkeypatch.setattr(server, "NOTIFY_SEND", str(script))

    def launch(pid: int, *argv: str) -> None:
        (proc / str(pid)).mkdir()
        (proc / str(pid) / "cmdline").write_bytes(b"\0".join(arg.encode() for arg in argv) + b"\0")

    def shown() -> list[str]:
        return log.read_text().splitlines() if log.exists() else []

    return launch, shown


def test_a_phone_notification_shows_on_the_desktop(desktop):
    launch, shown = desktop
    launch(10, "firefox", "-P", "default")
    assert server.phone_notify({"package": "org.telegram.messenger", "app": "Telegram", "title": "ana", "text": "-oi"}) == {"shown": True}
    assert shown() == ["--app-name|Telegram|--icon|phone|--|ana|-oi|"]


def test_whatsapp_stays_on_the_phone_while_it_is_open_on_the_desktop(desktop):
    launch, shown = desktop
    note = {"package": "com.whatsapp", "app": "WhatsApp", "title": "ana", "text": "oi"}
    assert server.phone_notify(note)["shown"] is True
    launch(11, ".firefox-wrapped", "-P", "whatsapp", "--new-instance", "--url", "https://web.whatsapp.com")
    assert server.phone_notify(note) == {"shown": False, "reason": "WhatsApp is open on the desktop"}
    assert len(shown()) == 1


def test_a_phone_notification_needs_a_package_and_words(desktop):
    with pytest.raises(ValueError):
        server.phone_notify({"package": "org.example", "title": " ", "text": ""})
    with pytest.raises(ValueError):
        server.phone_notify({"title": "ana", "text": "oi"})


def test_only_the_phone_forwards_notifications(bridge, desktop, monkeypatch):
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "100.64.0.9")
    status, body = fetch(f"{bridge}/api/phone/notify", json.dumps({"package": "a.b", "title": "x"}).encode(), {"Content-Type": "application/json"})
    assert status == 403
    assert body["error"] == "only the phone forwards its notifications"
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "127.0.0.1")
    status, body = fetch(f"{bridge}/api/phone/notify", json.dumps({"package": "a.b", "title": "x"}).encode(), {"Content-Type": "application/json"})
    assert (status, body) == (200, {"shown": True})


def test_phone_notifications_are_on_until_switched_off(bridge, desktop, forward, monkeypatch):
    _, shown = desktop
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "127.0.0.1")
    assert fetch(f"{bridge}/api/phone/forward") == (200, {"on": True})
    assert post_json(f"{bridge}/api/phone/forward", {"on": False}) == (200, {"on": False})
    assert json.loads(server.FORWARD_FILE.read_text()) == {"on": False}
    assert forward.read_text().splitlines() == ["changed"]
    assert fetch(f"{bridge}/api/phone/forward") == (200, {"on": False})
    note = {"package": "org.telegram.messenger", "app": "Telegram", "title": "ana", "text": "oi"}
    assert server.phone_notify(note) == {"shown": False, "reason": "phone notifications are off"}
    assert shown() == []
    server.FORWARD_FILE.write_text(json.dumps({"on": True}))
    assert server.phone_notify(note) == {"shown": True}
    assert len(shown()) == 1


def test_only_the_phone_switches_its_notifications_over_the_bridge(bridge, monkeypatch):
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "100.64.0.9")
    status, body = post_json(f"{bridge}/api/phone/forward", {"on": False})
    assert (status, body["error"]) == (403, "only the phone switches its notifications over the bridge; the desktop uses phone-forward")
    assert not server.FORWARD_FILE.exists()
    assert fetch(f"{bridge}/api/phone/forward") == (200, {"on": True})
    monkeypatch.setattr(server, "PHONE_MEDIA_PEERS", "127.0.0.1")
    assert post_json(f"{bridge}/api/phone/forward", {"on": "no"})[0] == 400


def test_a_broken_forward_file_reads_as_on(forward):
    server.FORWARD_FILE.write_text("{not json")
    assert server.forward_on() is True
    server.FORWARD_FILE.write_text(json.dumps({"on": None}))
    assert server.forward_on() is True
