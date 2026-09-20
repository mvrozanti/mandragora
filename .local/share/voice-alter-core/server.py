#!/usr/bin/env python3
from __future__ import annotations

import os

import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

LISTEN_HOST = os.environ.get("VOICE_ALTER_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("VOICE_ALTER_LISTEN_PORT", "8095"))

app = FastAPI(title="voice-alter-core")


class Hub:
    def __init__(self) -> None:
        self.sessions: dict[str, dict[str, set[WebSocket]]] = {}

    def join(self, session: str, role: str, ws: WebSocket) -> None:
        room = self.sessions.setdefault(session, {"source": set(), "sink": set()})
        room[role].add(ws)

    def leave(self, session: str, role: str, ws: WebSocket) -> None:
        room = self.sessions.get(session)
        if not room:
            return
        room[role].discard(ws)
        if not room["source"] and not room["sink"]:
            self.sessions.pop(session, None)

    def sinks(self, session: str) -> set[WebSocket]:
        room = self.sessions.get(session)
        return set(room["sink"]) if room else set()


hub = Hub()


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok", "service": "voice-alter-core", "sessions": len(hub.sessions)}


@app.websocket("/ws")
async def ws(websocket: WebSocket) -> None:
    session = websocket.query_params.get("session", "")
    role = websocket.query_params.get("role", "")
    await websocket.accept()
    if not session or role not in ("source", "sink"):
        await websocket.close(code=4004)
        return
    hub.join(session, role, websocket)
    try:
        while True:
            message = await websocket.receive()
            if message["type"] == "websocket.disconnect":
                break
            if role == "source" and message.get("bytes") is not None:
                payload = message["bytes"]
                for sink in hub.sinks(session):
                    try:
                        await sink.send_bytes(payload)
                    except Exception:
                        hub.leave(session, "sink", sink)
    except WebSocketDisconnect:
        pass
    finally:
        hub.leave(session, role, websocket)


def main() -> int:
    uvicorn.run(app, host=LISTEN_HOST, port=LISTEN_PORT, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
