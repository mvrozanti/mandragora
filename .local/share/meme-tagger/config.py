"""Env-driven configuration. Mirrors llm-via-telegram/config.py shape."""
from __future__ import annotations

import logging
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

TELEGRAM_BOT_TOKEN: str = os.getenv("TELEGRAM_BOT_TOKEN", "")
ALLOWED_USER_ID: str = os.getenv("ALLOWED_USER_ID", "")

OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
VLM_MODEL: str = os.getenv("MEME_TAGGER_VLM_MODEL", "qwen2.5vl:7b")
VLM_TIMEOUT_SECONDS: float = float(os.getenv("MEME_TAGGER_VLM_TIMEOUT", "180"))
VLM_TEMPERATURE: float = float(os.getenv("MEME_TAGGER_VLM_TEMPERATURE", "0.1"))
VLM_MAX_EDGE: int = int(os.getenv("MEME_TAGGER_VLM_MAX_EDGE", "1280"))

GPU_LOCK_EXPECTED_SECONDS: float = float(os.getenv("MEME_TAGGER_GPU_EXPECTED", "20"))
GPU_BUSY_RETRY_SECONDS: float = float(os.getenv("MEME_TAGGER_BUSY_RETRY", "5"))
GPU_BUSY_RETRY_CAP_SECONDS: float = float(os.getenv("MEME_TAGGER_BUSY_CAP", "1800"))

BASE_DIR: Path = Path(__file__).resolve().parent
STATE_DIR: Path = Path(os.getenv("MEME_TAGGER_STATE_DIR", str(Path.home() / ".local/share/meme-tagger")))
DATA_DIR: Path = Path(os.getenv("MEME_TAGGER_DATA_DIR", str(STATE_DIR / "data")))
LOG_DIR: Path = Path(os.getenv("MEME_TAGGER_LOG_DIR", str(STATE_DIR / "logs")))
DB_PATH: Path = DATA_DIR / "bot.db"

INCOMING_ROOT: Path = Path(os.getenv("MEME_TAGGER_INCOMING_ROOT", str(Path.home() / "Pictures/tagged")))

LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()

for d in (STATE_DIR, DATA_DIR, LOG_DIR, INCOMING_ROOT):
    d.mkdir(parents=True, exist_ok=True)


def validate_config() -> list[str]:
    errors: list[str] = []
    if not TELEGRAM_BOT_TOKEN:
        errors.append("TELEGRAM_BOT_TOKEN is not set")
    if not ALLOWED_USER_ID:
        errors.append("ALLOWED_USER_ID is not set")
    return errors


def validate_cli_config() -> list[str]:
    return []
