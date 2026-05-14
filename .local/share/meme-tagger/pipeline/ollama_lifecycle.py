"""Ollama VRAM coordination: poll /api/ps, force-unload via keep_alive=0.

The shared gpu_lock only guarantees acquire/release exclusion. It does not
free VRAM: Ollama keeps the model resident until keep_alive expires (default
5 min). Releasing the lock with the model still in VRAM lets the next holder
fault with CUDA OOM. evict_model is called while holding the lock, before
release.
"""
from __future__ import annotations

import asyncio
import logging

import httpx

log = logging.getLogger(__name__)


async def wait_for_unload(base_url: str, model: str, timeout: float = 10.0) -> bool:
    base = base_url.rstrip("/")
    deadline = asyncio.get_running_loop().time() + timeout
    async with httpx.AsyncClient(timeout=5.0) as client:
        while True:
            try:
                resp = await client.get(f"{base}/api/ps")
                resp.raise_for_status()
                loaded = [m.get("name", "") for m in resp.json().get("models", [])]
                if not any(name == model or name.startswith(f"{model}:") for name in loaded):
                    return True
            except httpx.HTTPError as exc:
                log.debug("ps poll failed: %s", exc)
            if asyncio.get_running_loop().time() >= deadline:
                log.warning("model %s still loaded after %.1fs", model, timeout)
                return False
            await asyncio.sleep(0.2)


async def evict_others(base_url: str, keep: str) -> None:
    base = base_url.rstrip("/")
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{base}/api/ps")
            resp.raise_for_status()
            loaded = [m.get("name", "") for m in resp.json().get("models", [])]
    except httpx.HTTPError as exc:
        log.debug("evict_others: ps failed: %s", exc)
        return
    for name in loaded:
        if name != keep and not name.startswith(f"{keep}:"):
            log.info("evicting %s to free VRAM before loading %s", name, keep)
            await evict_model(base_url, name)


async def evict_model(base_url: str, model: str, timeout: float = 30.0) -> bool:
    base = base_url.rstrip("/")
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            await client.post(
                f"{base}/api/generate",
                json={"model": model, "keep_alive": 0},
            )
    except httpx.HTTPError as exc:
        log.debug("evict POST failed (model may already be unloaded): %s", exc)
    return await wait_for_unload(base_url, model, timeout=timeout)
