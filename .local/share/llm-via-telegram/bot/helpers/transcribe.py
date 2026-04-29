"""Local speech-to-text via faster-whisper. Multilingual (auto-detect EN/PT)."""

import asyncio
import logging
import os
import threading

import config

logger = logging.getLogger(__name__)

_model = None
_model_lock = threading.Lock()


def _load_model():
    global _model
    if _model is not None:
        return _model
    with _model_lock:
        if _model is not None:
            return _model
        from faster_whisper import WhisperModel
        logger.info(
            "loading faster-whisper model=%s device=%s compute=%s",
            config.STT_MODEL, config.STT_DEVICE, config.STT_COMPUTE_TYPE,
        )
        _model = WhisperModel(
            config.STT_MODEL,
            device=config.STT_DEVICE,
            compute_type=config.STT_COMPUTE_TYPE,
            download_root=config.STT_CACHE_DIR,
        )
        return _model


def _transcribe_blocking(audio_path: str) -> tuple[str, str, float]:
    model = _load_model()
    segments, info = model.transcribe(
        audio_path,
        language=None,
        task="transcribe",
        vad_filter=True,
        beam_size=5,
    )
    text = "".join(seg.text for seg in segments).strip()
    return text, info.language, float(info.language_probability)


async def transcribe(audio_path: str) -> tuple[str, str, float]:
    """Transcribe audio. Returns (text, language_code, confidence)."""
    if not os.path.exists(audio_path):
        raise FileNotFoundError(audio_path)
    return await asyncio.to_thread(_transcribe_blocking, audio_path)
