import logging
import os
from pathlib import Path
from typing import Optional

import httpx

log = logging.getLogger("gource.remote")

DESKTOP_URL = os.environ.get("DESKTOP_RENDERER_URL", "").rstrip("/")
HEALTH_TIMEOUT = float(os.environ.get("DESKTOP_RENDERER_TIMEOUT_S", "2"))
RENDER_TIMEOUT = float(os.environ.get("DESKTOP_RENDERER_RENDER_TIMEOUT_S", "600"))


def configured() -> bool:
    return bool(DESKTOP_URL)


async def healthy() -> bool:
    if not DESKTOP_URL:
        return False
    try:
        async with httpx.AsyncClient(timeout=HEALTH_TIMEOUT) as c:
            r = await c.get(f"{DESKTOP_URL}/healthz")
            return r.status_code == 200
    except Exception as e:
        log.info("desktop renderer unreachable: %s", e)
        return False


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
    payload = {
        "job_id": job_id,
        "date_min": date_min,
        "date_max": date_max,
        "length_s": length_s,
        "width": width,
        "height": height,
    }
    if progress_cb:
        await progress_cb(0.10, "uploading job to desktop renderer")

    tmp = out_path.with_suffix(".part")
    if tmp.exists():
        tmp.unlink()

    async with httpx.AsyncClient(timeout=httpx.Timeout(RENDER_TIMEOUT, connect=HEALTH_TIMEOUT)) as c:
        async with c.stream("POST", f"{DESKTOP_URL}/render-sync", json=payload) as r:
            if r.status_code != 200:
                body = (await r.aread()).decode("utf-8", "replace")[:400]
                raise RuntimeError(f"desktop renderer returned {r.status_code}: {body}")
            total = int(r.headers.get("Content-Length", "0") or 0)
            written = 0
            with tmp.open("wb") as f:
                async for chunk in r.aiter_bytes():
                    if not chunk:
                        continue
                    f.write(chunk)
                    written += len(chunk)
                    if progress_cb and total:
                        pct = 0.10 + min(0.85, 0.85 * written / total)
                        await progress_cb(pct, f"streaming mp4 ({written // 1024}KB)")

    tmp.rename(out_path)
    if progress_cb:
        await progress_cb(0.98, "received from desktop")
