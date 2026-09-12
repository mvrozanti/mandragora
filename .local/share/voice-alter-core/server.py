#!/usr/bin/env python3
from __future__ import annotations

import os

import uvicorn
from fastapi import FastAPI, WebSocket

LISTEN_HOST = os.environ.get("VOICE_ALTER_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("VOICE_ALTER_LISTEN_PORT", "8095"))

app = FastAPI(title="voice-alter-core")


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok", "service": "voice-alter-core", "mode": "passthrough"}


@app.websocket("/ws")
async def ws(websocket: WebSocket) -> None:
    await websocket.accept()
    while True:
        message = await websocket.receive()
        if message["type"] == "websocket.disconnect":
            break
        if message.get("bytes") is not None:
            await websocket.send_bytes(message["bytes"])


def main() -> int:
    uvicorn.run(app, host=LISTEN_HOST, port=LISTEN_PORT, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
