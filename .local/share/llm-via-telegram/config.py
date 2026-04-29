"""Configuration loader. Reads from .env file and environment variables."""

import logging
import os

from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

# ── Required ──────────────────────────────────────────────────────

TELEGRAM_BOT_TOKEN: str = os.getenv("TELEGRAM_BOT_TOKEN", "")
ALLOWED_USER_ID: str = os.getenv("ALLOWED_USER_ID", "")

# ── Optional (with defaults) ──────────────────────────────────────

OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
AGENTS_MD_PATH: str = os.getenv("AGENTS_MD_PATH", "/etc/nixos/mandragora/AGENTS.md")
LOCAL_LLM_MD_PATH: str = os.getenv("LOCAL_LLM_MD_PATH", "/etc/nixos/mandragora/local-llm.md")
OLLAMA_MODEL: str = os.getenv("OLLAMA_MODEL", "gpt-oss:20b")
GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")
SUDO_CACHE_TIMEOUT: int = int(os.getenv("SUDO_CACHE_TIMEOUT", "300"))
MPV_SOCKET: str = os.getenv("MPV_SOCKET", "/tmp/mpvsocket")
DISPLAY_ENV: str = os.getenv("DISPLAY", ":0")
XAUTHORITY: str | None = os.getenv("XAUTHORITY")
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()

# ── Data directories ──────────────────────────────────────────────

BASE_DIR: str = os.path.dirname(os.path.abspath(__file__))
DATA_DIR: str = os.getenv("LLM_VIA_TELEGRAM_DATA_DIR", os.path.join(BASE_DIR, "data"))
DB_PATH: str = os.path.join(DATA_DIR, "bot.db")

os.makedirs(DATA_DIR, exist_ok=True)

# ── Speech-to-text (faster-whisper) ───────────────────────────────

STT_MODEL: str = os.getenv("STT_MODEL", "small")
STT_DEVICE: str = os.getenv("STT_DEVICE", "cpu")
STT_COMPUTE_TYPE: str = os.getenv("STT_COMPUTE_TYPE", "int8")
STT_CACHE_DIR: str = os.getenv("STT_CACHE_DIR", os.path.join(DATA_DIR, "whisper-models"))

os.makedirs(STT_CACHE_DIR, exist_ok=True)


def validate_config() -> list[str]:
    """Return a list of missing required config items (empty = all good)."""
    errors: list[str] = []
    if not TELEGRAM_BOT_TOKEN:
        errors.append("TELEGRAM_BOT_TOKEN is not set")
    if not ALLOWED_USER_ID:
        errors.append("ALLOWED_USER_ID is not set")
    return errors


def x11_env() -> dict[str, str]:
    """Return a dict of X11-related environment variables for child processes."""
    env = {"DISPLAY": DISPLAY_ENV}
    if XAUTHORITY:
        env["XAUTHORITY"] = XAUTHORITY
    return env
