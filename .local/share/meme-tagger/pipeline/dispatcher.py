"""Single entry: tag_image(path). Handles cache, OCR, gpu-lock, VLM, sidecar, eviction."""
from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from pathlib import Path

import config
from gpu_lock import GpuBusy, gpu_lock

from . import ocr, ollama_lifecycle, postprocess, preprocess, schema, sidecar, vlm

log = logging.getLogger(__name__)


@dataclass
class TagResult:
    tagged: schema.TaggedImage
    sidecar_path: Path
    cached: bool
    elapsed_seconds: float


async def tag_image(image_path: Path, *, force: bool = False) -> TagResult:
    started = time.time()
    p = preprocess.probe(image_path)

    if not force:
        cached = sidecar.already_tagged(image_path, p.sha256)
        if cached is not None:
            return TagResult(
                tagged=cached,
                sidecar_path=sidecar.sidecar_path(image_path),
                cached=True,
                elapsed_seconds=time.time() - started,
            )

    loop = asyncio.get_running_loop()
    ocr_phrases = await loop.run_in_executor(None, ocr.extract, image_path)
    ocr_text = ocr.render_for_prompt(ocr_phrases)

    image_bytes = await loop.run_in_executor(
        None, preprocess.load_representative_frame, image_path, config.VLM_MAX_EDGE
    )

    prompt = vlm.render_prompt(ocr_text)
    source = schema.Source(
        path=str(image_path.resolve()),
        sha256=p.sha256,
        mtime=p.mtime,
        size_bytes=p.size_bytes,
        format=p.format,
        width=p.width,
        height=p.height,
        frames=p.frames,
    )
    model = schema.Model(
        vlm=config.VLM_MODEL,
        ocr=ocr.version_string() if ocr_phrases else "",
        prompt_version=vlm.PROMPT_VERSION,
    )

    async with gpu_lock.acquire_async(
        "meme-tagger", expected_seconds=config.GPU_LOCK_EXPECTED_SECONDS
    ):
        await ollama_lifecycle.evict_others(config.OLLAMA_BASE_URL, keep=config.VLM_MODEL)
        try:
            vlm_raw = await vlm.call(
                base_url=config.OLLAMA_BASE_URL,
                model=config.VLM_MODEL,
                image_bytes=image_bytes,
                prompt=prompt,
                temperature=config.VLM_TEMPERATURE,
                timeout_seconds=config.VLM_TIMEOUT_SECONDS,
            )
        finally:
            await ollama_lifecycle.evict_model(config.OLLAMA_BASE_URL, config.VLM_MODEL)

    tagged = postprocess.build_tagged_image(
        vlm_raw=vlm_raw,
        ocr_phrases=ocr_phrases,
        source=source,
        model=model,
    )
    out = sidecar.write_all(image_path, tagged)
    return TagResult(
        tagged=tagged,
        sidecar_path=out,
        cached=False,
        elapsed_seconds=time.time() - started,
    )


async def tag_image_with_retry(
    image_path: Path,
    *,
    force: bool = False,
    on_busy=None,
) -> TagResult:
    elapsed_busy = 0.0
    while True:
        try:
            return await tag_image(image_path, force=force)
        except GpuBusy as busy:
            if on_busy is not None:
                await on_busy(busy)
            if elapsed_busy >= config.GPU_BUSY_RETRY_CAP_SECONDS:
                raise
            wait = config.GPU_BUSY_RETRY_SECONDS
            await asyncio.sleep(wait)
            elapsed_busy += wait
