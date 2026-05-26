import asyncio
import hashlib
import logging
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

import uvicorn
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles

import config
from tts import get_engine

try:
    from gpu_lock import gpu_lock, GpuBusy
    HAS_GPU_LOCK = True
except ImportError:
    HAS_GPU_LOCK = False

logger = logging.getLogger(__name__)

app = FastAPI(title="mandragora-tts-clone-core", version="0.2")

_NAME_RE = re.compile(r"^[a-zA-Z0-9 _\-.]{1,64}$")


def _safe_user(remote_user: str | None) -> str:
    name = (remote_user or "").strip() or config.ANON_USER
    return re.sub(r"[^a-zA-Z0-9._-]", "_", name)[:64] or config.ANON_USER


def _user_refs_dir(user: str) -> Path:
    d = Path(config.REFS_DIR) / user
    d.mkdir(parents=True, exist_ok=True)
    return d


def _validate_name(name: str) -> str:
    name = (name or "").strip()
    if not _NAME_RE.match(name):
        raise HTTPException(status_code=400, detail="name must be 1-64 chars: letters, digits, space, _ - .")
    if name in (".", ".."):
        raise HTTPException(status_code=400, detail="invalid name")
    return name


def _ref_path(user: str, name: str) -> Path:
    return _user_refs_dir(user) / f"{name}.wav"


def _list_refs(user: str) -> list[dict]:
    d = _user_refs_dir(user)
    items = []
    for p in sorted(d.glob("*.wav")):
        st = p.stat()
        items.append({
            "name": p.stem,
            "size_bytes": st.st_size,
            "mtime": st.st_mtime,
        })
    return items


async def _ffmpeg(*args: str) -> None:
    proc = await asyncio.create_subprocess_exec(
        "ffmpeg", "-y", "-loglevel", "error", *args,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    _, err = await proc.communicate()
    if proc.returncode != 0:
        raise RuntimeError(err.decode("utf-8", "replace") or "ffmpeg failed")


async def _to_reference_wav(src: Path, dst: Path) -> float:
    await _ffmpeg("-i", str(src), "-ac", "1", "-ar", "24000", str(dst))
    proc = await asyncio.create_subprocess_exec(
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=nw=1:nk=1", str(dst),
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    out, _ = await proc.communicate()
    return float(out.decode().strip() or "0")


@app.get("/healthz")
def healthz():
    return {
        "ok": True,
        "model": config.F5_MODEL,
        "lang": config.F5_LANG or None,
        "model_loaded": get_engine().loaded,
    }


@app.get("/whoami")
def whoami(remote_user: str | None = Header(default=None, alias="Remote-User")):
    return Response(content=(remote_user or ""), media_type="text/plain")


@app.get("/status")
def status(remote_user: str | None = Header(default=None, alias="Remote-User")):
    user = _safe_user(remote_user)
    refs = _list_refs(user)
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
        "user": user,
        "ref_count": len(refs),
        "model_loaded": get_engine().loaded,
        "gpu_lock_holder": holder,
        "config": {
            "model": config.F5_MODEL,
            "lang": config.F5_LANG or None,
            "nfe_steps": config.F5_NFE_STEPS,
            "max_ref_seconds": config.MAX_REF_SECONDS,
            "max_gen_chars": config.MAX_GEN_CHARS,
        },
    }


@app.post("/warmup")
async def warmup_endpoint():
    if HAS_GPU_LOCK:
        try:
            async with gpu_lock.acquire_async(config.GPU_LOCK_NAME, expected_seconds=60):
                await asyncio.to_thread(get_engine().load)
        except GpuBusy as busy:
            raise HTTPException(status_code=503, detail=f"gpu busy: {busy}")
    else:
        await asyncio.to_thread(get_engine().load)
    return {"ok": True, "model_loaded": get_engine().loaded}


@app.get("/refs")
def list_refs(remote_user: str | None = Header(default=None, alias="Remote-User")):
    user = _safe_user(remote_user)
    return {"user": user, "refs": _list_refs(user)}


@app.post("/refs")
async def upload_ref(
    name: str = Form(...),
    audio: UploadFile = File(...),
    remote_user: str | None = Header(default=None, alias="Remote-User"),
):
    user = _safe_user(remote_user)
    name = _validate_name(name)
    suffix = os.path.splitext(audio.filename or "")[1] or ".bin"
    tmp_fd, tmp_in = tempfile.mkstemp(prefix="ref-in-", suffix=suffix)
    written = 0
    try:
        with os.fdopen(tmp_fd, "wb") as f:
            while True:
                chunk = await audio.read(1024 * 1024)
                if not chunk:
                    break
                written += len(chunk)
                if written > config.MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="reference too large")
                f.write(chunk)
        if written == 0:
            raise HTTPException(status_code=400, detail="empty upload")

        dst = _ref_path(user, name)
        try:
            duration = await _to_reference_wav(Path(tmp_in), dst)
        except RuntimeError as e:
            raise HTTPException(status_code=400, detail=f"could not decode audio: {e}")

        warning = None
        if duration > config.MAX_REF_SECONDS:
            warning = f"reference is {duration:.1f}s — F5-TTS works best on 8–15s clips."
        elif duration < 3:
            warning = f"reference is only {duration:.1f}s — send 8–15s for best results."
        return {
            "user": user,
            "name": name,
            "duration_seconds": duration,
            "warning": warning,
            "bytes": written,
            "size_bytes": dst.stat().st_size,
        }
    finally:
        try:
            os.unlink(tmp_in)
        except OSError:
            pass


@app.delete("/refs/{name}")
def delete_ref(
    name: str,
    remote_user: str | None = Header(default=None, alias="Remote-User"),
):
    user = _safe_user(remote_user)
    name = _validate_name(name)
    p = _ref_path(user, name)
    if not p.is_file():
        raise HTTPException(status_code=404, detail="not found")
    p.unlink()
    return {"user": user, "name": name, "deleted": True}


@app.get("/refs/{name}")
def get_ref(
    name: str,
    remote_user: str | None = Header(default=None, alias="Remote-User"),
):
    user = _safe_user(remote_user)
    name = _validate_name(name)
    p = _ref_path(user, name)
    if not p.is_file():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(
        str(p),
        media_type="audio/wav",
        headers={"Content-Disposition": f'inline; filename="{name}.wav"'},
    )


@app.post("/synthesize")
async def synthesize(
    text: str = Form(..., min_length=1, max_length=config.MAX_GEN_CHARS),
    ref_name: str = Form(...),
    ref_text: str = Form(default=""),
    seed: int = Form(default=-1),
    remote_user: str | None = Header(default=None, alias="Remote-User"),
):
    user = _safe_user(remote_user)
    ref_name = _validate_name(ref_name)
    ref = _ref_path(user, ref_name)
    if not ref.is_file():
        raise HTTPException(status_code=404, detail=f"reference '{ref_name}' not found")

    ts = time.strftime("%Y%m%d-%H%M%S")
    digest = hashlib.sha256(f"{ref_name}\0{text}".encode("utf-8")).hexdigest()[:8]
    out_wav = Path(config.OUT_DIR) / f"{user}_{ts}_{digest}.wav"

    estimated = max(config.F5_NFE_STEPS * 0.4 + len(text) * 0.05, 8.0)
    started = time.monotonic()
    try:
        if HAS_GPU_LOCK:
            try:
                async with gpu_lock.acquire_async(config.GPU_LOCK_NAME, expected_seconds=estimated):
                    await asyncio.to_thread(
                        get_engine().infer, ref, text, out_wav, ref_text, seed,
                    )
            except GpuBusy as busy:
                raise HTTPException(status_code=503, detail=f"gpu busy: {busy}")
        else:
            await asyncio.to_thread(
                get_engine().infer, ref, text, out_wav, ref_text, seed,
            )
    except Exception as e:
        logger.exception("synthesis failed")
        raise HTTPException(status_code=500, detail=f"synthesis failed: {e}")
    elapsed = time.monotonic() - started

    if not out_wav.is_file():
        raise HTTPException(status_code=500, detail="synthesis produced no output")

    return FileResponse(
        str(out_wav),
        media_type="audio/wav",
        headers={
            "Content-Disposition": f'inline; filename="{out_wav.name}"',
            "X-Elapsed-Seconds": f"{elapsed:.2f}",
            "X-Ref-Name": ref_name,
        },
    )


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
    logger.info("tts-clone-core listening on %s:%d", config.BIND_HOST, config.BIND_PORT)
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
