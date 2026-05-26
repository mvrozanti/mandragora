import os

from dotenv import load_dotenv

load_dotenv()

BASE_DIR: str = os.path.dirname(os.path.abspath(__file__))

BIND_HOST: str = os.getenv("STT_CORE_BIND_HOST", "0.0.0.0")
BIND_PORT: int = int(os.getenv("STT_CORE_BIND_PORT", "8091"))

STT_MODEL: str = os.getenv("STT_MODEL", "large-v3")
STT_DEVICE: str = os.getenv("STT_DEVICE", "cuda")
STT_COMPUTE_TYPE: str = os.getenv("STT_COMPUTE_TYPE", "float16")
STT_BEAM_SIZE: int = int(os.getenv("STT_BEAM_SIZE", "5"))
STT_VAD: bool = os.getenv("STT_VAD", "1") not in ("", "0", "false", "False")

STATE_DIR: str = os.getenv("STT_CORE_STATE_DIR", os.path.join(BASE_DIR, "state"))
DATA_DIR: str = os.getenv("STT_CORE_DATA_DIR", os.path.join(STATE_DIR, "data"))
STT_CACHE_DIR: str = os.getenv("STT_CACHE_DIR", os.path.join(DATA_DIR, "whisper-models"))

ALLOWED_LANGS: tuple[str, ...] = tuple(
    lang.strip().lower()
    for lang in os.getenv("STT_ALLOWED_LANGS", "en,pt").split(",")
    if lang.strip()
)

GPU_LOCK_NAME: str = os.getenv("GPU_LOCK_NAME", "stt-core")
GPU_EXPECTED_SECONDS: float = float(os.getenv("GPU_EXPECTED_SECONDS", "30"))

MAX_UPLOAD_BYTES: int = int(os.getenv("STT_MAX_UPLOAD_BYTES", str(200 * 1024 * 1024)))

LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()

os.makedirs(STATE_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(STT_CACHE_DIR, exist_ok=True)
