import os

from dotenv import load_dotenv

load_dotenv()

TELEGRAM_BOT_TOKEN: str = os.getenv("TELEGRAM_BOT_TOKEN", "")
ALLOWED_USER_ID: str = os.getenv("ALLOWED_USER_ID", "")

STT_MODEL: str = os.getenv("STT_MODEL", "large-v3")
STT_DEVICE: str = os.getenv("STT_DEVICE", "cuda")
STT_COMPUTE_TYPE: str = os.getenv("STT_COMPUTE_TYPE", "float16")
STT_BEAM_SIZE: int = int(os.getenv("STT_BEAM_SIZE", "5"))
STT_VAD: bool = os.getenv("STT_VAD", "1") not in ("", "0", "false", "False")

BASE_DIR: str = os.path.dirname(os.path.abspath(__file__))
DATA_DIR: str = os.getenv("STT_VIA_TELEGRAM_DATA_DIR", os.path.join(BASE_DIR, "data"))
STT_CACHE_DIR: str = os.getenv("STT_CACHE_DIR", os.path.join(DATA_DIR, "whisper-models"))

ALLOWED_LANGS: tuple[str, ...] = tuple(
    lang.strip().lower()
    for lang in os.getenv("STT_ALLOWED_LANGS", "en,pt").split(",")
    if lang.strip()
)

GPU_LOCK_NAME: str = os.getenv("GPU_LOCK_NAME", "stt-via-telegram")
GPU_EXPECTED_SECONDS: float = float(os.getenv("GPU_EXPECTED_SECONDS", "30"))

LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()

os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(STT_CACHE_DIR, exist_ok=True)


def validate_config() -> list[str]:
    errors: list[str] = []
    if not TELEGRAM_BOT_TOKEN:
        errors.append("TELEGRAM_BOT_TOKEN is not set")
    if not ALLOWED_USER_ID:
        errors.append("ALLOWED_USER_ID is not set")
    return errors
