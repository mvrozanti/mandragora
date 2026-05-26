import logging
import os
import tempfile
import time
from dataclasses import asdict

import uvicorn
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

import config
from transcribe import transcribe, warmup, is_loaded

try:
    from gpu_lock import gpu_lock, GpuBusy
    HAS_GPU_LOCK = True
except ImportError:
    HAS_GPU_LOCK = False

logger = logging.getLogger(__name__)

app = FastAPI(title="mandragora-stt-core", version="0.1")


@app.get("/healthz")
def healthz():
    return {
        "ok": True,
        "model": config.STT_MODEL,
        "device": config.STT_DEVICE,
        "compute_type": config.STT_COMPUTE_TYPE,
        "model_loaded": is_loaded(),
    }


@app.get("/whoami")
def whoami(remote_user: str | None = Header(default=None, alias="Remote-User")):
    return Response(content=(remote_user or ""), media_type="text/plain")


@app.get("/status")
def status():
    holder = None
    if HAS_GPU_LOCK:
        h = gpu_lock.current_holder()
        if h:
            holder = {
                "name": h.get("name"),
                "pid": h.get("pid"),
                "held_seconds": time.time() - h.get("since", time.time()),
            }
    return {
        "model_loaded": is_loaded(),
        "gpu_lock_holder": holder,
        "config": {
            "model": config.STT_MODEL,
            "device": config.STT_DEVICE,
            "compute_type": config.STT_COMPUTE_TYPE,
            "beam_size": config.STT_BEAM_SIZE,
            "vad": config.STT_VAD,
            "allowed_langs": list(config.ALLOWED_LANGS),
        },
    }


@app.post("/warmup")
async def warmup_endpoint():
    if HAS_GPU_LOCK:
        try:
            async with gpu_lock.acquire_async(config.GPU_LOCK_NAME, expected_seconds=60):
                import asyncio
                await asyncio.to_thread(warmup)
        except GpuBusy as busy:
            raise HTTPException(status_code=503, detail=f"gpu busy: {busy}")
    else:
        import asyncio
        await asyncio.to_thread(warmup)
    return {"ok": True, "model_loaded": is_loaded()}


@app.post("/transcribe")
async def transcribe_endpoint(
    audio: UploadFile = File(...),
    language: str | None = Form(default=None),
    task: str = Form(default="transcribe"),
):
    if task not in ("transcribe", "translate"):
        raise HTTPException(status_code=400, detail="task must be 'transcribe' or 'translate'")
    if language and language not in config.ALLOWED_LANGS and len(language) != 2:
        raise HTTPException(status_code=400, detail=f"language must be 2-letter code; allowed hint: {config.ALLOWED_LANGS}")

    suffix = os.path.splitext(audio.filename or "")[1] or ".bin"
    tmp_fd, tmp_path = tempfile.mkstemp(prefix="stt-core-", suffix=suffix)
    written = 0
    try:
        with os.fdopen(tmp_fd, "wb") as f:
            while True:
                chunk = await audio.read(1024 * 1024)
                if not chunk:
                    break
                written += len(chunk)
                if written > config.MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="audio too large")
                f.write(chunk)
        if written == 0:
            raise HTTPException(status_code=400, detail="empty upload")

        started = time.monotonic()
        if HAS_GPU_LOCK:
            try:
                async with gpu_lock.acquire_async(
                    config.GPU_LOCK_NAME,
                    expected_seconds=config.GPU_EXPECTED_SECONDS,
                ):
                    result = await transcribe(tmp_path, language=language, task=task)
            except GpuBusy as busy:
                raise HTTPException(status_code=503, detail=f"gpu busy: {busy}")
        else:
            result = await transcribe(tmp_path, language=language, task=task)
        elapsed = time.monotonic() - started
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    return JSONResponse({
        **asdict(result),
        "elapsed_seconds": elapsed,
        "rtf": elapsed / result.duration if result.duration > 0 else 0,
        "bytes": written,
    })


app.mount("/static", StaticFiles(directory=os.path.join(os.path.dirname(__file__), "static")), name="static")


@app.get("/")
def index():
    return FileResponse(os.path.join(os.path.dirname(__file__), "static/index.html"))


def main():
    logging.basicConfig(
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        level=getattr(logging, config.LOG_LEVEL, logging.INFO),
    )
    for noisy in ("httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
    logger.info("stt-core listening on %s:%d", config.BIND_HOST, config.BIND_PORT)
    uvicorn.run(
        app,
        host=config.BIND_HOST,
        port=config.BIND_PORT,
        log_level=config.LOG_LEVEL.lower(),
        proxy_headers=True,
        forwarded_allow_ips="*",
    )


if __name__ == "__main__":
    main()
