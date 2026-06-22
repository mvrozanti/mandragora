import asyncio
import logging
import os
import shlex
from pathlib import Path
from typing import Optional

log = logging.getLogger("gource.local")

REPO_URL = os.environ.get("REPO_URL", "https://github.com/mvrozanti/mandragora.git")
REPO_DIR = Path(os.environ.get("REPO_DIR", "/repo/mandragora"))


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


async def _probe_duration(path: Path) -> float:
    rc, out, e = await _run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        timeout=30,
    )
    if rc != 0:
        raise RuntimeError(f"ffprobe failed: {e.strip()}")
    try:
        return float(out.strip())
    except ValueError:
        raise RuntimeError(f"ffprobe gave no duration: {out.strip()!r}")


async def _retime(src: Path, dst: Path, target_s: float, fps: int, crf: int) -> None:
    d = await _probe_duration(src)
    if d <= 0:
        raise RuntimeError("source duration non-positive")
    if abs(d - target_s) <= 0.5:
        src.rename(dst)
        return
    factor = target_s / d
    log.info("retime %.2fs -> %.2fs (factor %.4f)", d, target_s, factor)
    rc, _, e = await _run(
        ["ffmpeg", "-y", "-i", str(src),
         "-filter:v", f"setpts={factor:.6f}*PTS",
         "-an", "-r", str(fps),
         "-c:v", "libx264", "-preset", "veryfast", "-crf", str(crf),
         "-pix_fmt", "yuv420p", "-movflags", "+faststart",
         "-loglevel", "error", str(dst)],
        timeout=max(120, int(target_s) * 6 + 60),
    )
    if rc != 0:
        raise RuntimeError(f"retime ffmpeg failed: {e.strip()[-400:]}")
    src.unlink(missing_ok=True)


async def ensure_repo() -> Path:
    REPO_DIR.parent.mkdir(parents=True, exist_ok=True)
    if not (REPO_DIR / ".git").exists():
        log.info("cloning %s into %s", REPO_URL, REPO_DIR)
        rc, _, e = await _run(["git", "clone", REPO_URL, str(REPO_DIR)], timeout=900)
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
    raw_path = out_path.with_name(out_path.stem + ".raw.mp4")

    gource_cmd = [
        "xvfb-run", "-a", "-s", f"-screen 0 {width}x{height}x24",
        "gource",
        str(repo),
        *(["--start-date", date_min] if date_min else []),
        *(["--stop-date", date_max] if date_max else []),
        "--seconds-per-day", f"{seconds_per_day:.4f}",
        "--auto-skip-seconds", "1",
        "--max-files", "0",
        "--hide", "mouse,progress,filenames",
        f"-{width}x{height}",
        "--output-framerate", str(fps),
        "--output-ppm-stream", "-",
        "--multi-sampling",
        "--bloom-multiplier", "0.7",
        "--bloom-intensity", "0.4",
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
        str(raw_path),
    ]

    shell_cmd = " ".join(shlex.quote(a) for a in gource_cmd) + \
                " | " + " ".join(shlex.quote(a) for a in ffmpeg_cmd)
    log.info("pipeline: %s", shell_cmd)

    proc = await asyncio.create_subprocess_shell(
        shell_cmd,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )

    deadline = max(60, length_s * 6 + 60)
    cancelled = False

    async def _watchdog():
        nonlocal cancelled
        waited = 0
        while proc.returncode is None and waited < deadline:
            await asyncio.sleep(2)
            waited += 2
            if progress_cb:
                pct = 0.15 + min(0.78, 0.78 * waited / max(1, length_s * 2))
                await progress_cb(pct, f"encoding ({waited}s elapsed)")
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

    if cancelled:
        raise RuntimeError(f"render watchdog killed pipeline after {deadline}s")
    if rc != 0:
        raise RuntimeError(f"pipeline exited {rc}: {stderr_data.decode('utf-8', 'replace').strip()[-400:]}")
    if not raw_path.exists() or raw_path.stat().st_size < 1024:
        raise RuntimeError("output mp4 missing or too small")
    if progress_cb:
        await progress_cb(0.90, "normalizing length")
    try:
        await _retime(raw_path, out_path, float(length_s), fps, 23)
    finally:
        raw_path.unlink(missing_ok=True)
    if progress_cb:
        await progress_cb(0.98, "finalizing")
