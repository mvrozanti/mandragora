import os
import shutil
import subprocess
from pathlib import Path

from fastapi import FastAPI, HTTPException, Header
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

MODELS_DIR = Path(os.environ.get("TTS_MODELS_DIR", "/models"))
DEFAULT_VOICE = os.environ.get("TTS_DEFAULT_VOICE", "en_US-lessac-medium")
PIPER_BIN = shutil.which("piper") or "/usr/local/bin/piper"


def list_voices() -> list[str]:
    return sorted(p.stem for p in MODELS_DIR.glob("*.onnx"))


def model_path(name: str) -> Path:
    path = MODELS_DIR / f"{name}.onnx"
    if not path.is_file():
        raise HTTPException(status_code=404, detail=f"unknown voice: {name}")
    return path


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


def _synthesize_bytes(text: str, voice_name: str) -> bytes:
    model = model_path(voice_name)
    proc = subprocess.run(
        [PIPER_BIN, "--model", str(model), "--output_file", "-"],
        input=text.encode("utf-8"),
        capture_output=True,
        timeout=120,
    )
    if proc.returncode != 0:
        raise HTTPException(
            status_code=500,
            detail=f"piper failed: {proc.stderr.decode('utf-8', 'replace')[:500]}",
        )
    return proc.stdout


@app.post("/synthesize")
def synthesize(req: SynthesizeRequest):
    voice_name = req.voice or DEFAULT_VOICE
    audio = _synthesize_bytes(req.text, voice_name)
    return Response(
        content=audio,
        media_type="audio/wav",
        headers={"Content-Disposition": f'inline; filename="{voice_name}.wav"'},
    )


class OpenAISpeechRequest(BaseModel):
    model: str | None = None
    input: str = Field(..., min_length=1, max_length=10_000)
    voice: str | None = None
    response_format: str | None = None
    speed: float | None = None


@app.get("/v1/models")
def openai_models():
    voices = list_voices()
    return {
        "object": "list",
        "data": [{"id": v, "object": "model", "owned_by": "piper"} for v in voices],
    }


@app.post("/v1/audio/speech")
def openai_speech(req: OpenAISpeechRequest):
    voice_name = req.voice or req.model or DEFAULT_VOICE
    audio = _synthesize_bytes(req.input, voice_name)
    return Response(content=audio, media_type="audio/wav")


app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
def index():
    return FileResponse("static/index.html")
