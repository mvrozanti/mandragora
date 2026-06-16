import asyncio
import hashlib
import json
import logging
import os
import time
from collections import deque
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field, field_validator

import render_local
import render_remote

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)
log = logging.getLogger("gource.api")

CACHE_DIR = Path(os.environ.get("CACHE_DIR", "/cache"))
CACHE_DIR.mkdir(parents=True, exist_ok=True)

DEFAULTS = {
    "length_s": 60,
    "width": 1024,
    "height": 1024,
    "date_min": None,
    "date_max": None,
}

LOCAL_CAPS = {
    "length_s_min": 10,
    "length_s_max": int(os.environ.get("LOCAL_MAX_LENGTH_S", "120")),
    "width_min": 480,
    "width_max": int(os.environ.get("LOCAL_MAX_WIDTH", "1280")),
    "height_min": 480,
    "height_max": int(os.environ.get("LOCAL_MAX_HEIGHT", "1280")),
}

REMOTE_CAPS = {
    "length_s_min": 10,
    "length_s_max": 300,
    "width_min": 480,
    "width_max": 1920,
    "height_min": 480,
    "height_max": 1920,
}

RATE_LIMIT_PER_HOUR = int(os.environ.get("RATE_LIMIT_PER_HOUR", "10"))
ALLOWED_RESOLUTIONS = {(720, 720), (1024, 1024), (1280, 720), (1920, 1080)}

app = FastAPI(title="gource-api")


class RenderParams(BaseModel):
    date_min: Optional[str] = None
    date_max: Optional[str] = None
    length_s: int = Field(default=DEFAULTS["length_s"], ge=10, le=300)
    width: int = Field(default=DEFAULTS["width"], ge=240, le=1920)
    height: int = Field(default=DEFAULTS["height"], ge=240, le=1920)
    force: bool = False  # bypass cache + re-render (NOT part of hash_params -> overwrites same cache key)

    @field_validator("date_min", "date_max")
    @classmethod
    def _date_shape(cls, v: Optional[str]) -> Optional[str]:
        if v is None or v == "":
            return None
        if len(v) != 10 or v[4] != "-" or v[7] != "-":
            raise ValueError("expected YYYY-MM-DD")
        y, m, d = v[:4], v[5:7], v[8:10]
        if not (y.isdigit() and m.isdigit() and d.isdigit()):
            raise ValueError("expected YYYY-MM-DD")
        return v


@dataclass
class Job:
    job_id: str
    params: RenderParams
    state: str = "queued"  # queued | running | done | failed
    progress: float = 0.0
    message: str = ""
    error: Optional[str] = None
    backend: Optional[str] = None  # desktop | vps | cache
    queue_position: int = 0
    started_at: float = 0.0
    finished_at: float = 0.0
    video_url: Optional[str] = None


_jobs: dict[str, Job] = {}
_queue: deque[str] = deque()
_worker_lock = asyncio.Lock()
_worker_task: Optional[asyncio.Task] = None
_loop_started = False

_rate_buckets: dict[str, deque[float]] = {}


def hash_params(p: RenderParams) -> str:
    canon = json.dumps(
        {
            "v": 1,
            "date_min": p.date_min,
            "date_max": p.date_max,
            "length_s": p.length_s,
            "width": p.width,
            "height": p.height,
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canon.encode("utf-8")).hexdigest()[:24]


def cache_path(job_id: str) -> Path:
    return CACHE_DIR / f"{job_id}.mp4"


def sidecar_path(job_id: str) -> Path:
    return CACHE_DIR / f"{job_id}.json"


def _write_sidecar(job_id: str, j: "Job") -> None:
    try:
        sidecar_path(job_id).write_text(json.dumps({
            "job_id": job_id,
            "params": j.params.model_dump(),
            "backend": j.backend,
            "finished_at": j.finished_at or time.time(),
        }, separators=(",", ":")))
    except Exception as e:
        log.warning("[%s] sidecar write failed: %s", job_id, e)


def _read_sidecar(job_id: str) -> Optional[dict]:
    p = sidecar_path(job_id)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text())
    except Exception:
        return None


def client_ip(req: Request) -> str:
    fwd = req.headers.get("X-Forwarded-For", "")
    if fwd:
        return fwd.split(",")[0].strip()
    return req.client.host if req.client else "unknown"


def check_rate(ip: str) -> Optional[int]:
    now = time.time()
    bucket = _rate_buckets.setdefault(ip, deque())
    while bucket and now - bucket[0] > 3600:
        bucket.popleft()
    if len(bucket) >= RATE_LIMIT_PER_HOUR:
        retry = int(3600 - (now - bucket[0])) + 1
        return retry
    bucket.append(now)
    return None


def serialize_job(j: Job) -> dict:
    d = asdict(j)
    d["params"] = j.params.model_dump()
    if j.state == "done":
        d["video_url"] = f"/api/gource/video/{j.job_id}"
    return d


async def _set_progress(job_id: str, frac: float, message: str = "") -> None:
    j = _jobs.get(job_id)
    if not j:
        return
    j.progress = max(j.progress, frac)
    if message:
        j.message = message


def _validate_caps(p: RenderParams, *, allow_remote: bool) -> None:
    caps = REMOTE_CAPS if allow_remote else LOCAL_CAPS
    if not (caps["length_s_min"] <= p.length_s <= caps["length_s_max"]):
        raise HTTPException(400, f"length_s out of range [{caps['length_s_min']}, {caps['length_s_max']}]")
    if not (caps["width_min"] <= p.width <= caps["width_max"]):
        raise HTTPException(400, f"width out of range [{caps['width_min']}, {caps['width_max']}]")
    if not (caps["height_min"] <= p.height <= caps["height_max"]):
        raise HTTPException(400, f"height out of range [{caps['height_min']}, {caps['height_max']}]")
    if (p.width, p.height) not in ALLOWED_RESOLUTIONS:
        raise HTTPException(400, f"resolution {p.width}x{p.height} not allowed")
    if p.date_min and p.date_max and p.date_min > p.date_max:
        raise HTTPException(400, "date_min must be <= date_max")


async def _run_one(job_id: str) -> None:
    j = _jobs[job_id]
    j.state = "running"
    j.started_at = time.time()
    j.progress = 0.02
    out = cache_path(job_id)
    try:
        if render_remote.configured() and await render_remote.healthy():
            j.backend = "desktop"
            log.info("[%s] dispatching to desktop renderer", job_id)
            try:
                await render_remote.render(
                    job_id=job_id,
                    date_min=j.params.date_min,
                    date_max=j.params.date_max,
                    length_s=j.params.length_s,
                    width=j.params.width,
                    height=j.params.height,
                    out_path=out,
                    progress_cb=lambda f, m="": _set_progress(job_id, f, m),
                )
            except Exception as e:
                log.warning("[%s] desktop render failed (%s) — falling back to local", job_id, e)
                j.backend = "vps"
                j.message = f"desktop failed: {e}; retrying locally"
                _validate_caps(j.params, allow_remote=False)
                await render_local.render(
                    job_id=job_id,
                    date_min=j.params.date_min,
                    date_max=j.params.date_max,
                    length_s=j.params.length_s,
                    width=j.params.width,
                    height=j.params.height,
                    out_path=out,
                    progress_cb=lambda f, m="": _set_progress(job_id, f, m),
                )
        else:
            j.backend = "vps"
            log.info("[%s] desktop unavailable, rendering locally", job_id)
            _validate_caps(j.params, allow_remote=False)
            await render_local.render(
                job_id=job_id,
                date_min=j.params.date_min,
                date_max=j.params.date_max,
                length_s=j.params.length_s,
                width=j.params.width,
                height=j.params.height,
                out_path=out,
                progress_cb=lambda f, m="": _set_progress(job_id, f, m),
            )

        j.state = "done"
        j.progress = 1.0
        j.message = "ready"
        j.video_url = f"/api/gource/video/{job_id}"
        _write_sidecar(job_id, j)
    except HTTPException as e:
        j.state = "failed"
        j.error = e.detail if isinstance(e.detail, str) else str(e.detail)
    except Exception as e:
        log.exception("[%s] render failed", job_id)
        j.state = "failed"
        j.error = str(e)
    finally:
        j.finished_at = time.time()


async def _worker_loop() -> None:
    log.info("worker loop started")
    while True:
        if not _queue:
            await asyncio.sleep(0.25)
            continue
        async with _worker_lock:
            if not _queue:
                continue
            jid = _queue.popleft()
        for idx, pending in enumerate(_queue, start=1):
            _jobs[pending].queue_position = idx
        try:
            await _run_one(jid)
        except Exception:
            log.exception("[%s] worker crash", jid)


@app.on_event("startup")
async def _startup() -> None:
    global _worker_task, _loop_started
    if _loop_started:
        return
    _loop_started = True
    _worker_task = asyncio.create_task(_worker_loop())
    log.info("gource-api ready (cache=%s, desktop_url=%s, rate=%d/h)",
             CACHE_DIR, os.environ.get("DESKTOP_RENDERER_URL", ""), RATE_LIMIT_PER_HOUR)


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True, "queue_depth": len(_queue), "cached": len(list(CACHE_DIR.glob("*.mp4")))}


@app.get("/defaults")
def defaults() -> dict:
    return {
        "defaults": DEFAULTS,
        "local_caps": LOCAL_CAPS,
        "remote_caps": REMOTE_CAPS,
        "allowed_resolutions": [f"{w}x{h}" for (w, h) in sorted(ALLOWED_RESOLUTIONS)],
        "rate_limit_per_hour": RATE_LIMIT_PER_HOUR,
    }


@app.get("/latest")
def latest() -> JSONResponse:
    mp4s = list(CACHE_DIR.glob("*.mp4"))
    if not mp4s:
        raise HTTPException(404, "no renders cached yet")
    mp4s.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    for mp4 in mp4s:
        jid = mp4.stem
        sc = _read_sidecar(jid)
        if sc:
            sc["video_url"] = f"/api/gource/video/{jid}"
            sc["state"] = "done"
            return JSONResponse(sc)
    newest = mp4s[0]
    jid = newest.stem
    return JSONResponse({
        "job_id": jid,
        "params": None,
        "backend": None,
        "finished_at": newest.stat().st_mtime,
        "video_url": f"/api/gource/video/{jid}",
        "state": "done",
    })


@app.post("/render")
async def render_endpoint(p: RenderParams, request: Request) -> JSONResponse:
    _validate_caps(p, allow_remote=True)
    jid = hash_params(p)
    existing = _jobs.get(jid)
    if not p.force:
        if existing and existing.state == "done" and cache_path(jid).exists():
            return JSONResponse(serialize_job(existing))
        if cache_path(jid).exists():
            j = Job(job_id=jid, params=p, state="done", backend="cache",
                    progress=1.0, message="cache hit",
                    video_url=f"/api/gource/video/{jid}")
            _jobs[jid] = j
            return JSONResponse(serialize_job(j))

    retry = check_rate(client_ip(request))
    if retry is not None:
        return JSONResponse(
            {"detail": f"rate limited: {RATE_LIMIT_PER_HOUR}/hour"},
            status_code=429,
            headers={"Retry-After": str(retry)},
        )

    if existing and existing.state in ("queued", "running"):
        return JSONResponse(serialize_job(existing))

    j = Job(job_id=jid, params=p, state="queued", message="queued")
    _jobs[jid] = j
    _queue.append(jid)
    j.queue_position = len(_queue)
    return JSONResponse(serialize_job(j))


@app.get("/status/{job_id}")
def status(job_id: str) -> JSONResponse:
    j = _jobs.get(job_id)
    if j:
        return JSONResponse(serialize_job(j))
    if cache_path(job_id).exists():
        params = RenderParams()
        synth = Job(job_id=job_id, params=params, state="done",
                    backend="cache", progress=1.0, message="cache hit",
                    video_url=f"/api/gource/video/{job_id}")
        _jobs[job_id] = synth
        return JSONResponse(serialize_job(synth))
    raise HTTPException(404, "unknown job")


@app.get("/video/{job_id}")
def video(job_id: str) -> Response:
    p = cache_path(job_id)
    if not p.exists():
        raise HTTPException(404, "not ready")
    return FileResponse(
        p,
        media_type="video/mp4",
        headers={"Cache-Control": "public, max-age=2592000, immutable"},
    )
