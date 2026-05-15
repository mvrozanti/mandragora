"""Env-driven configuration for the meme-tagger CLI."""
from __future__ import annotations

import logging
import os
from pathlib import Path

logger = logging.getLogger(__name__)

OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
VLM_MODEL: str = os.getenv("MEME_TAGGER_VLM_MODEL", "qwen2.5vl:7b")
VLM_TIMEOUT_SECONDS: float = float(os.getenv("MEME_TAGGER_VLM_TIMEOUT", "600"))
VLM_TEMPERATURE: float = float(os.getenv("MEME_TAGGER_VLM_TEMPERATURE", "0.1"))
VLM_MAX_EDGE: int = int(os.getenv("MEME_TAGGER_VLM_MAX_EDGE", "1280"))

GPU_LOCK_EXPECTED_SECONDS: float = float(os.getenv("MEME_TAGGER_GPU_EXPECTED", "20"))
GPU_BUSY_RETRY_SECONDS: float = float(os.getenv("MEME_TAGGER_BUSY_RETRY", "5"))
GPU_BUSY_RETRY_CAP_SECONDS: float = float(os.getenv("MEME_TAGGER_BUSY_CAP", "1800"))

BASE_DIR: Path = Path(__file__).resolve().parent
STATE_DIR: Path = Path(os.getenv("MEME_TAGGER_STATE_DIR", str(Path.home() / ".local/share/meme-tagger")))
LOG_DIR: Path = Path(os.getenv("MEME_TAGGER_LOG_DIR", str(STATE_DIR / "logs")))

LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()
