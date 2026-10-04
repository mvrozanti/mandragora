#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import json
import os
import secrets
import urllib.request
from collections import deque
from pathlib import Path

import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from websockets.asyncio.client import connect as ws_connect

LISTEN_HOST = os.environ.get("VOICE_ALTER_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("VOICE_ALTER_LISTEN_PORT", "8095"))
RVC_WS = os.environ.get("VOICE_ALTER_RVC_WS", "ws://127.0.0.1:8098/ws")
RVC_HEALTH = os.environ.get("VOICE_ALTER_RVC_HEALTH", "http://127.0.0.1:8098/healthz")
RVC_LOAD_TIMEOUT_S = float(os.environ.get("VOICE_ALTER_RVC_LOAD_TIMEOUT", "45"))
RVC_RETRY_S = 10.0
STATE_DIR = os.environ.get("STATE_DIRECTORY", "")
SETTINGS_FILE = Path(STATE_DIR) / "settings.json" if STATE_DIR else None

MODES = {
    "bypass", "pitch", "deeper", "higher", "helium", "demon",
    "robot", "radio", "telephone", "echo", "reverb", "mcbaldiee",
}
RVC_MODES = {"mcbaldiee"}
DEFAULTS = {"mode": "bypass", "pitch": 0, "buffer": 80, "gain": 100}
RANGES = {"pitch": (-12, 12), "buffer": (20, 500), "gain": (0, 300)}
AUDIO_BACKLOG = 50

app = FastAPI(title="voice-alter-core")


def log(msg: str) -> None:
    print(msg, flush=True)


def merge_settings(current: dict, incoming: object) -> dict:
    merged = dict(current)
    if not isinstance(incoming, dict):
        return merged
    mode = incoming.get("mode")
    if mode in MODES:
        merged["mode"] = mode
    for key, (lo, hi) in RANGES.items():
        value = incoming.get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            merged[key] = int(min(hi, max(lo, round(value))))
    return merged


def load_settings() -> dict:
    if SETTINGS_FILE is None or not SETTINGS_FILE.is_file():
        return dict(DEFAULTS)
    try:
        return merge_settings(DEFAULTS, json.loads(SETTINGS_FILE.read_text()))
    except (OSError, ValueError):
        return dict(DEFAULTS)


class Peer:
    def __init__(self, websocket: WebSocket) -> None:
        self.ws = websocket
        self.id = secrets.token_hex(4)
        self.control: deque[str] = deque()
        self.audio: deque[bytes] = deque(maxlen=AUDIO_BACKLOG)
        self.wake = asyncio.Event()

    def send_control(self, text: str) -> None:
        self.control.append(text)
        self.wake.set()

    def send_audio(self, payload: bytes) -> None:
        self.audio.append(payload)
        self.wake.set()

    async def pump(self) -> None:
        while True:
            if not self.control and not self.audio:
                self.wake.clear()
                await self.wake.wait()
                continue
            if self.control:
                await self.ws.send_text(self.control.popleft())
            else:
                await self.ws.send_bytes(self.audio.popleft())


class RvcBridge:
    def __init__(self, room: Room) -> None:
        self.room = room
        self.status = "off"
        self.task: asyncio.Task | None = None
        self.outbox: deque[bytes] = deque(maxlen=AUDIO_BACKLOG)
        self.wake = asyncio.Event()

    def want(self, on: bool) -> None:
        if on and self.task is None:
            self.task = asyncio.create_task(self.run())
        elif not on and self.task is not None:
            self.task.cancel()
            self.task = None
            self.outbox.clear()
            self.set_status("off")

    def set_status(self, status: str) -> None:
        if status != self.status:
            self.status = status
            log(f"rvc: {status}")
            self.room.broadcast_state()

    def send(self, payload: bytes) -> None:
        if self.status == "ready":
            self.outbox.append(payload)
            self.wake.set()

    async def loaded(self) -> bool:
        def probe() -> bool:
            with urllib.request.urlopen(RVC_HEALTH, timeout=2) as resp:
                return bool(json.load(resp).get("loaded"))

        try:
            return await asyncio.to_thread(probe)
        except Exception:
            return False

    async def wait_loaded(self) -> bool:
        deadline = asyncio.get_running_loop().time() + RVC_LOAD_TIMEOUT_S
        while asyncio.get_running_loop().time() < deadline:
            if await self.loaded():
                return True
            await asyncio.sleep(1)
        return False

    async def forward_output(self, sink) -> None:
        async for message in sink:
            if isinstance(message, bytes):
                self.room.fanout(message)

    async def forward_input(self, source) -> None:
        while True:
            if not self.outbox:
                self.wake.clear()
                await self.wake.wait()
                continue
            await source.send(self.outbox.popleft())

    async def run(self) -> None:
        while True:
            try:
                self.set_status("loading")
                async with ws_connect(f"{RVC_WS}?role=sink", max_size=None) as sink, \
                        ws_connect(f"{RVC_WS}?role=source", max_size=None) as source:
                    if not await self.wait_loaded():
                        self.set_status("unavailable")
                    else:
                        self.outbox.clear()
                        self.set_status("ready")
                        done, pending = await asyncio.wait(
                            [
                                asyncio.create_task(self.forward_output(sink)),
                                asyncio.create_task(self.forward_input(source)),
                            ],
                            return_when=asyncio.FIRST_COMPLETED,
                        )
                        for task in pending:
                            task.cancel()
                        for task in done:
                            task.result()
                        self.set_status("down")
            except asyncio.CancelledError:
                raise
            except OSError as exc:
                log(f"rvc connect failed: {exc}")
                self.set_status("down")
            except Exception as exc:
                log(f"rvc bridge error: {exc!r}")
                self.set_status("down")
            await asyncio.sleep(RVC_RETRY_S)


class Room:
    def __init__(self) -> None:
        self.peers: dict[str, Peer] = {}
        self.mic: str | None = None
        self.settings = load_settings()
        self.rvc = RvcBridge(self)
        self.save_task: asyncio.Task | None = None

    def snapshot(self) -> dict:
        return {
            "t": "state",
            "mic": self.mic,
            "peers": len(self.peers),
            "settings": self.settings,
            "rvc": self.rvc.status,
        }

    def broadcast_state(self) -> None:
        text = json.dumps(self.snapshot())
        for peer in self.peers.values():
            peer.send_control(text)

    def fanout(self, payload: bytes) -> None:
        for peer_id, peer in self.peers.items():
            if peer_id != self.mic:
                peer.send_audio(payload)

    def from_mic(self, payload: bytes) -> None:
        if self.settings["mode"] in RVC_MODES:
            self.rvc.send(payload)
        else:
            self.fanout(payload)

    def sync(self) -> None:
        self.rvc.want(self.mic is not None and self.settings["mode"] in RVC_MODES)
        self.broadcast_state()

    def join(self, peer: Peer) -> None:
        self.peers[peer.id] = peer
        peer.send_control(json.dumps({"t": "hello", "id": peer.id}))
        self.sync()

    def leave(self, peer: Peer) -> None:
        self.peers.pop(peer.id, None)
        if self.mic == peer.id:
            self.mic = None
        self.sync()

    def handle(self, peer: Peer, text: str) -> None:
        try:
            message = json.loads(text)
        except ValueError:
            return
        if not isinstance(message, dict):
            return
        kind = message.get("t")
        if kind == "claim":
            self.mic = peer.id
        elif kind == "release":
            if self.mic == peer.id:
                self.mic = None
        elif kind == "set":
            self.settings = merge_settings(self.settings, message.get("settings"))
            self.schedule_save()
        else:
            return
        self.sync()

    def schedule_save(self) -> None:
        if SETTINGS_FILE is None:
            return
        if self.save_task is None or self.save_task.done():
            self.save_task = asyncio.create_task(self.save(SETTINGS_FILE))

    async def save(self, path: Path) -> None:
        await asyncio.sleep(1)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.settings))
        tmp.replace(path)


room = Room()


@app.get("/healthz")
async def healthz() -> dict:
    return {
        "status": "ok",
        "service": "voice-alter-core",
        "peers": len(room.peers),
        "mic": room.mic is not None,
        "mode": room.settings["mode"],
        "rvc": room.rvc.status,
    }


@app.websocket("/ws")
async def ws(websocket: WebSocket) -> None:
    await websocket.accept()
    peer = Peer(websocket)
    pump = asyncio.create_task(peer.pump())
    room.join(peer)
    try:
        while True:
            message = await websocket.receive()
            if message["type"] == "websocket.disconnect":
                break
            payload = message.get("bytes")
            if payload is not None:
                if room.mic == peer.id:
                    room.from_mic(payload)
                continue
            text = message.get("text")
            if text:
                room.handle(peer, text)
    except WebSocketDisconnect:
        pass
    finally:
        pump.cancel()
        room.leave(peer)


def main() -> int:
    uvicorn.run(app, host=LISTEN_HOST, port=LISTEN_PORT, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
