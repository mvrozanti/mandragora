"""Desktop-side gource renderer.

HTTP server that the VPS gource-api proxies render jobs to over
tailscale. Runs gource → ffmpeg locally on the workstation (where it
finishes in a fraction of the time the Oracle ARM VPS would take) and
streams the resulting MP4 back to the caller.

The on-disk cache mirrors the VPS one: jobs are keyed by sha256 of
the params, and an identical re-request is satisfied straight from
disk.

Endpoints:
  GET  /healthz                    cheap liveness probe
  POST /render-sync  {params}      block until MP4 ready, stream it back
  GET  /defaults                   tell caller our caps

Caps are wider than the VPS fallback's because the desktop can
actually handle them.
"""

import asyncio
import hashlib
import json
import logging
import os
import shlex
import time
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field, field_validator

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("gource-renderer")

REPO_PATH = Path(os.environ.get("GOURCE_REPO_PATH", "/etc/nixos/mandragora"))
CACHE_DIR = Path(os.environ.get("GOURCE_CACHE_DIR", "/var/lib/gource-renderer/cache"))
CACHE_DIR.mkdir(parents=True, exist_ok=True)
LISTEN_HOST = os.environ.get("GOURCE_LISTEN_HOST", "100.115.80.79")
LISTEN_PORT = int(os.environ.get("GOURCE_LISTEN_PORT", "9991"))

CAPS = {
    "length_s_min": 10,
    "length_s_max": 300,
    "width_min": 240,
    "width_max": 1920,
    "height_min": 240,
    "height_max": 1920,
}
ALLOWED_RESOLUTIONS = {(720, 720), (1024, 1024), (1280, 720), (1920, 1080)}

_render_lock = asyncio.Lock()

app = FastAPI(title="gource-renderer")


class RenderParams(BaseModel):
    job_id: Optional[str] = None
    date_min: Optional[str] = None
    date_max: Optional[str] = None
    length_s: int = Field(default=60, ge=10, le=300)
    width: int = Field(default=1024, ge=240, le=1920)
    height: int = Field(default=1024, ge=240, le=1920)

    @field_validator("date_min", "date_max")
    @classmethod
    def _shape(cls, v: Optional[str]) -> Optional[str]:
        if v in (None, ""):
            return None
        if len(v) != 10 or v[4] != "-" or v[7] != "-":
            raise ValueError("expected YYYY-MM-DD")
        return v


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


async def _run(cmd: list[str], cwd: Optional[Path] = None, timeout: float = 600) -> tuple[int, str, str]:
    log.info("$ %s", " ".join(cmd))
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        cwd=str(cwd) if cwd else None,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise RuntimeError(f"timeout after {timeout}s running {cmd[0]}")
    return proc.returncode or 0, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")


def _git(*args: str) -> list[str]:
    return ["git", "-c", "safe.directory=*", *args]


async def _resolve_head(repo: Path, date_max: Optional[str]) -> str:
    if date_max:
        rc, out, e = await _run(
            _git("rev-list", "-n", "1", f"--before={date_max} 23:59:59", "HEAD"),
            cwd=repo, timeout=30,
        )
        if rc != 0:
            raise RuntimeError(f"git rev-list failed: {e.strip()}")
        sha = out.strip().splitlines()[0] if out.strip() else ""
        if not sha:
            raise RuntimeError(f"no commit at or before {date_max}")
        return sha
    rc, out, e = await _run(_git("rev-parse", "HEAD"), cwd=repo, timeout=15)
    if rc != 0:
        raise RuntimeError(f"git rev-parse failed: {e.strip()}")
    return out.strip()


async def _days_in_window(repo: Path, head: str, date_min: Optional[str]) -> int:
    args = _git("log", "--pretty=format:%ct")
    if date_min:
        args.append(f"--since={date_min}")
    args.append(head)
    rc, out, e = await _run(args, cwd=repo, timeout=60)
    if rc != 0:
        raise RuntimeError(f"git log probe failed: {e.strip()}")
    timestamps = [int(line) for line in out.splitlines() if line.strip().isdigit()]
    if not timestamps:
        return 0
    span = max(timestamps) - min(timestamps)
    return max(1, span // 86400 + 1)


async def _render_to(p: RenderParams, out_path: Path) -> None:
    if (p.width, p.height) not in ALLOWED_RESOLUTIONS:
        raise HTTPException(400, f"resolution {p.width}x{p.height} not allowed")

    repo = REPO_PATH
    if not (repo / ".git").exists() and not (repo / "HEAD").exists():
        raise HTTPException(500, f"GOURCE_REPO_PATH={repo} is not a git repo")

    head = await _resolve_head(repo, p.date_max)
    days = await _days_in_window(repo, head, p.date_min)
    if days == 0:
        raise HTTPException(400, "no commits in the selected window")

    seconds_per_day = max(0.01, p.length_s / float(days))
    fps = 60

    gource_args = [
        "gource",
        str(repo),
        *(["--start-date", p.date_min] if p.date_min else []),
        *(["--stop-date", p.date_max] if p.date_max else []),
        "--seconds-per-day", f"{seconds_per_day:.4f}",
        "--auto-skip-seconds", "1",
        "--max-files", "0",
        "--hide", "mouse,progress,filenames",
        f"-{p.width}x{p.height}",
        "--output-framerate", str(fps),
        "--output-ppm-stream", "-",
        "--multi-sampling",
        "--bloom-multiplier", "0.7",
        "--bloom-intensity", "0.4",
    ]

    ffmpeg_args = [
        "ffmpeg", "-y",
        "-f", "image2pipe",
        "-vcodec", "ppm",
        "-r", str(fps),
        "-i", "-",
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "21",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        "-loglevel", "error",
        str(out_path),
    ]

    display = f":{99 + (hash(out_path.name) % 50)}"
    xvfb_args = ["Xvfb", display, "-screen", "0", f"{p.width}x{p.height}x24",
                 "+extension", "GLX", "+extension", "RANDR", "+extension", "RENDER",
                 "-nolisten", "tcp", "-noreset"]
    gource_str = " ".join(shlex.quote(a) for a in gource_args)
    ffmpeg_str = " ".join(shlex.quote(a) for a in ffmpeg_args)
    xvfb_str = " ".join(shlex.quote(a) for a in xvfb_args)
    shell_cmd = (
        f"{xvfb_str} >/tmp/xvfb-{display.lstrip(':')}.log 2>&1 & "
        f"XVFB_PID=$!; "
        f"trap 'kill $XVFB_PID 2>/dev/null; wait $XVFB_PID 2>/dev/null' EXIT; "
        f"for i in 1 2 3 4 5 6 7 8 9 10; do "
        f"  [ -S /tmp/.X11-unix/X{display.lstrip(':')} ] && break; "
        f"  sleep 0.2; "
        f"done; "
        f"export DISPLAY={display}; "
        f"{gource_str} | {ffmpeg_str}"
    )
    log.info("pipeline: %s", shell_cmd)

    proc = await asyncio.create_subprocess_shell(
        shell_cmd,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )

    deadline = max(120, p.length_s * 6 + 60)
    cancelled = False

    async def _watchdog():
        nonlocal cancelled
        waited = 0
        while proc.returncode is None and waited < deadline:
            await asyncio.sleep(2)
            waited += 2
        if proc.returncode is None:
            log.error("watchdog killing render pipeline at %ds", waited)
            cancelled = True
            try:
                proc.kill()
            except ProcessLookupError:
                pass

    watchdog = asyncio.create_task(_watchdog())
    try:
        stderr_data = await proc.stderr.read() if proc.stderr else b""
        rc = await proc.wait()
    finally:
        watchdog.cancel()

    stderr_text = stderr_data.decode("utf-8", "replace").strip()
    if stderr_text:
        log.info("pipeline stderr: %s", stderr_text[-2000:])
    if cancelled:
        raise HTTPException(504, f"render watchdog killed pipeline after {deadline}s")
    if rc != 0:
        log.error("pipeline rc=%s stderr=%s", rc, stderr_text[-2000:])
        raise HTTPException(500, f"pipeline exited {rc}: {stderr_text[-400:]}")
    if not out_path.exists() or out_path.stat().st_size < 1024:
        size = out_path.stat().st_size if out_path.exists() else 0
        log.error("output mp4 missing or too small (size=%d) stderr=%s", size, stderr_text[-2000:])
        raise HTTPException(500, f"output mp4 missing or too small (size={size})")


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True, "cached": len(list(CACHE_DIR.glob("*.mp4")))}


@app.get("/defaults")
def defaults() -> dict:
    return {
        "caps": CAPS,
        "allowed_resolutions": [f"{w}x{h}" for (w, h) in sorted(ALLOWED_RESOLUTIONS)],
        "repo_path": str(REPO_PATH),
    }


@app.post("/render-sync")
async def render_sync(p: RenderParams, request: Request):
    jid = p.job_id or hash_params(p)
    out = CACHE_DIR / f"{jid}.mp4"
    if not out.exists():
        async with _render_lock:
            if not out.exists():
                tmp = out.with_name(out.stem + ".part.mp4")
                t0 = time.time()
                try:
                    await _render_to(p, tmp)
                except HTTPException:
                    if tmp.exists():
                        tmp.unlink()
                    raise
                tmp.rename(out)
                log.info("[%s] rendered in %.1fs (%d bytes)", jid, time.time() - t0, out.stat().st_size)
    return FileResponse(
        out,
        media_type="video/mp4",
        headers={
            "Content-Length": str(out.stat().st_size),
            "X-Job-Id": jid,
            "X-Backend": "desktop",
            "Cache-Control": "public, max-age=2592000, immutable",
        },
    )


def main() -> None:
    import uvicorn
    uvicorn.run(app, host=LISTEN_HOST, port=LISTEN_PORT, log_level=os.environ.get("LOG_LEVEL", "info").lower())


if __name__ == "__main__":
    main()
