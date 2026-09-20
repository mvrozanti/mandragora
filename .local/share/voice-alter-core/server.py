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
        self.source: set[WebSocket] = set()
        self.sink: set[WebSocket] = set()

    def join(self, role: str, ws: WebSocket) -> None:
        (self.source if role == "source" else self.sink).add(ws)

    def leave(self, role: str, ws: WebSocket) -> None:
        (self.source if role == "source" else self.sink).discard(ws)

    def sinks(self) -> set[WebSocket]:
        return set(self.sink)


hub = Hub()


@app.get("/healthz")
async def healthz() -> dict:
    return {
        "status": "ok",
        "service": "voice-alter-core",
        "sources": len(hub.source),
        "sinks": len(hub.sink),
    }


@app.websocket("/ws")
async def ws(websocket: WebSocket) -> None:
    role = websocket.query_params.get("role", "")
    await websocket.accept()
    if role not in ("source", "sink"):
        await websocket.close(code=4004)
        return
    hub.join(role, websocket)
    try:
        while True:
            message = await websocket.receive()
            if message["type"] == "websocket.disconnect":
                break
            if role == "source" and message.get("bytes") is not None:
                payload = message["bytes"]
                for sink in hub.sinks():
                    try:
                        await sink.send_bytes(payload)
                    except Exception:
                        hub.leave("sink", sink)
    except WebSocketDisconnect:
        pass
    finally:
        hub.leave(role, websocket)


def main() -> int:
    uvicorn.run(app, host=LISTEN_HOST, port=LISTEN_PORT, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
