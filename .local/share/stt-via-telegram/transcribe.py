import asyncio
import logging
import os
import threading
from dataclasses import dataclass

import config

logger = logging.getLogger(__name__)

_model = None
_model_lock = threading.Lock()


@dataclass
class TranscriptionResult:
    text: str
    language: str
    language_probability: float
    duration: float
    task: str


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


def _transcribe_blocking(audio_path: str, *, language: str | None, task: str) -> TranscriptionResult:
    model = _load_model()
    segments, info = model.transcribe(
        audio_path,
        language=language,
        task=task,
        vad_filter=config.STT_VAD,
        beam_size=config.STT_BEAM_SIZE,
    )
    text = "".join(seg.text for seg in segments).strip()
    return TranscriptionResult(
        text=text,
        language=info.language,
        language_probability=float(info.language_probability),
        duration=float(info.duration),
        task=task,
    )


async def transcribe(
    audio_path: str,
    *,
    language: str | None = None,
    task: str = "transcribe",
) -> TranscriptionResult:
    if not os.path.exists(audio_path):
        raise FileNotFoundError(audio_path)
    return await asyncio.to_thread(
        _transcribe_blocking, audio_path, language=language, task=task,
    )


def warmup() -> None:
    _load_model()
