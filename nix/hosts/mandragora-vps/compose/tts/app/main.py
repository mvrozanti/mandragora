import io
import os
import wave
from pathlib import Path

from fastapi import FastAPI, HTTPException, Header
from fastapi.responses import FileResponse, Response, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from piper import PiperVoice

MODELS_DIR = Path(os.environ.get("TTS_MODELS_DIR", "/models"))
DEFAULT_VOICE = os.environ.get("TTS_DEFAULT_VOICE", "en_US-lessac-medium")

_voices: dict[str, PiperVoice] = {}


def list_voices() -> list[str]:
    return sorted(p.stem for p in MODELS_DIR.glob("*.onnx"))


def get_voice(name: str) -> PiperVoice:
    if name not in _voices:
        path = MODELS_DIR / f"{name}.onnx"
        if not path.is_file():
            raise HTTPException(status_code=404, detail=f"unknown voice: {name}")
        _voices[name] = PiperVoice.load(str(path))
    return _voices[name]


class SynthesizeRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=10_000)
    voice: str | None = None


app = FastAPI(title="mandragora-tts", version="0.1")


@app.get("/healthz")
def healthz():
    return {"ok": True, "voices": list_voices()}


@app.get("/whoami")
def whoami(remote_user: str | None = Header(default=None, alias="Remote-User")):
    return Response(content=(remote_user or ""), media_type="text/plain")


@app.get("/voices")
def voices():
    return {"voices": list_voices(), "default": DEFAULT_VOICE}


@app.post("/synthesize")
def synthesize(req: SynthesizeRequest):
    voice_name = req.voice or DEFAULT_VOICE
    voice = get_voice(voice_name)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        voice.synthesize(req.text, wf)
    buf.seek(0)
    return Response(
        content=buf.read(),
        media_type="audio/wav",
        headers={"Content-Disposition": f'inline; filename="{voice_name}.wav"'},
    )


app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
def index():
    return FileResponse("static/index.html")
