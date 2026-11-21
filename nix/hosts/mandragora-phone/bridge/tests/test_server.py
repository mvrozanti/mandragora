import json
import sys
import threading
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
    assert result == {"text": "hello there", "language": "en", "duration": 1.5}
    content_type, body = stt.seen[0]
    assert content_type.startswith("multipart/form-data; boundary=")
    assert b'name="audio"; filename="speech.m4a"' in body
    assert b"\r\n\r\nAUDIO\r\n" in body


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
    assert (status, jobs) == (200, {"thumbs": [], "pull": [], "remove": []})
    assert "junk" not in server.media_index_items()["7"]

    status, body = post_json(f"{bridge}/api/phone/media/request", {"thumbs": ["7"], "pull": ["7"]})
    assert status == 200
    assert body["jobs"]["thumbs"] == ["7"] and body["jobs"]["pull"] == ["7"]
    status, jobs = fetch(f"{bridge}/api/phone/media/jobs")
    assert jobs == {"thumbs": ["7"], "pull": ["7"], "remove": []}

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
    assert jobs == {"thumbs": [], "pull": [], "remove": []}
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
