import asyncio
import logging
import os
from pathlib import Path
from typing import Optional

log = logging.getLogger("gource.local")

REPO_URL = os.environ.get("REPO_URL", "https://github.com/mvrozanti/mandragora.git")
REPO_DIR = Path(os.environ.get("REPO_DIR", "/repo/mandragora.git"))


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


async def ensure_repo() -> Path:
    REPO_DIR.parent.mkdir(parents=True, exist_ok=True)
    if not (REPO_DIR / "HEAD").exists():
        log.info("cloning %s into %s (bare)", REPO_URL, REPO_DIR)
        rc, _, e = await _run(["git", "clone", "--bare", REPO_URL, str(REPO_DIR)], timeout=900)
        if rc != 0:
            raise RuntimeError(f"git clone failed: {e.strip()}")
    else:
        rc, _, e = await _run(["git", "fetch", "--prune", "--all", "--tags"], cwd=REPO_DIR, timeout=300)
        if rc != 0:
            log.warning("git fetch failed (continuing with stale repo): %s", e.strip()[:200])
    return REPO_DIR


async def resolve_head_at(repo: Path, date_max: Optional[str]) -> str:
    if date_max:
        rc, out, e = await _run(
            ["git", "rev-list", "-n", "1", f"--before={date_max} 23:59:59", "HEAD"],
            cwd=repo, timeout=30,
        )
        if rc != 0:
            raise RuntimeError(f"git rev-list failed: {e.strip()}")
        sha = out.strip().splitlines()[0] if out.strip() else ""
        if not sha:
            raise RuntimeError(f"no commit at or before {date_max}")
        return sha
    rc, out, e = await _run(["git", "rev-parse", "HEAD"], cwd=repo, timeout=15)
    if rc != 0:
        raise RuntimeError(f"git rev-parse HEAD failed: {e.strip()}")
    return out.strip()


async def _days_in_window(repo: Path, head: str, date_min: Optional[str]) -> int:
    args = ["git", "log", "--pretty=format:%ct"]
    if date_min:
        args.append(f"--since={date_min}")
    args.append(head)
    rc, out, e = await _run(args, cwd=repo, timeout=60)
    if rc != 0:
        raise RuntimeError(f"git log probe failed: {e.strip()}")
    if not out.strip():
        return 0
    timestamps = [int(line) for line in out.splitlines() if line.strip().isdigit()]
    if not timestamps:
        return 0
    span = max(timestamps) - min(timestamps)
    return max(1, span // 86400 + 1)


async def render(
    *,
    job_id: str,
    date_min: Optional[str],
    date_max: Optional[str],
    length_s: int,
    width: int,
    height: int,
    out_path: Path,
    progress_cb=None,
) -> None:
    repo = await ensure_repo()
    if progress_cb:
        await progress_cb(0.05, "repo synced")

    head = await resolve_head_at(repo, date_max)
    days = await _days_in_window(repo, head, date_min)
    if days == 0:
        raise RuntimeError("no commits in the selected window")
    if progress_cb:
        await progress_cb(0.10, f"window covers {days} days ending at {head[:7]}")

    seconds_per_day = max(0.01, length_s / float(days))
    fps = 60

    gource_cmd = [
        "xvfb-run", "-a", "-s", f"-screen 0 {width}x{height}x24",
        "gource",
        str(repo),
        *([f"--start-date={date_min}"] if date_min else []),
        *([f"--stop-date={date_max}"] if date_max else []),
        f"--seconds-per-day={seconds_per_day:.4f}",
        "--auto-skip-seconds", "1",
        "--max-files", "0",
        "--hide", "mouse,progress,filenames",
        f"-{width}x{height}",
        "--output-framerate", str(fps),
        "--output-ppm-stream", "-",
        "--multi-sampling",
        "--bloom-multiplier", "0.7",
        "--bloom-intensity", "0.4",
        "--user-image-dir", "/dev/null",
    ]

    ffmpeg_cmd = [
        "ffmpeg", "-y",
        "-f", "image2pipe",
        "-vcodec", "ppm",
        "-r", str(fps),
        "-i", "-",
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "23",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        "-loglevel", "error",
        str(out_path),
    ]

    log.info("pipeline: %s | %s", " ".join(gource_cmd), " ".join(ffmpeg_cmd))
    gp = await asyncio.create_subprocess_exec(
        *gource_cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    fp = await asyncio.create_subprocess_exec(
        *ffmpeg_cmd,
        stdin=gp.stdout,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )
    if gp.stdout is not None:
        gp.stdout.close()

    deadline = max(60, length_s * 6 + 60)
    cancelled = False

    async def _watchdog():
        nonlocal cancelled
        waited = 0
        while fp.returncode is None and waited < deadline:
            await asyncio.sleep(2)
            waited += 2
            if progress_cb:
                pct = 0.15 + min(0.78, 0.78 * waited / max(1, length_s * 2))
                await progress_cb(pct, f"encoding ({waited}s elapsed)")
        if fp.returncode is None:
            log.error("watchdog killing render pipeline at %ds", waited)
            cancelled = True
            for p in (gp, fp):
                try:
                    p.kill()
                except ProcessLookupError:
                    pass

    watchdog = asyncio.create_task(_watchdog())
    try:
        f_stderr = await fp.stderr.read() if fp.stderr else b""
        f_rc = await fp.wait()
        g_rc = await gp.wait()
        g_stderr = await gp.stderr.read() if gp.stderr else b""
    finally:
        watchdog.cancel()

    if cancelled:
        raise RuntimeError(f"render watchdog killed pipeline after {deadline}s")
    if f_rc != 0:
        raise RuntimeError(f"ffmpeg exited {f_rc}: {f_stderr.decode('utf-8', 'replace').strip()[-400:]}")
    if g_rc not in (0, -15):
        log.warning("gource exited %s: %s", g_rc, g_stderr.decode('utf-8', 'replace').strip()[-200:])
    if not out_path.exists() or out_path.stat().st_size < 1024:
        raise RuntimeError("output mp4 missing or too small")
    if progress_cb:
        await progress_cb(0.98, "finalizing")
