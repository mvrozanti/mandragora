import os

from dotenv import load_dotenv

load_dotenv()

BASE_DIR: str = os.path.dirname(os.path.abspath(__file__))

BIND_HOST: str = os.getenv("TTS_CLONE_BIND_HOST", "0.0.0.0")
BIND_PORT: int = int(os.getenv("TTS_CLONE_BIND_PORT", "8092"))

STATE_DIR: str = os.getenv("TTS_CLONE_STATE_DIR", os.path.join(BASE_DIR, "state"))
REFS_DIR: str = os.path.join(STATE_DIR, "refs")
OUT_DIR: str = os.path.join(STATE_DIR, "out")
HF_CACHE_DIR: str = os.getenv("HF_HOME", os.path.join(STATE_DIR, "hf-cache"))

F5_MODEL: str = os.getenv("F5_MODEL", "F5TTS_v1_Base")
F5_LANG: str = os.getenv("F5_LANG", "").strip()
F5_CKPT_FILE: str = os.getenv("F5_CKPT_FILE", "").strip()
F5_VOCAB_FILE: str = os.getenv("F5_VOCAB_FILE", "").strip()
F5_NFE_STEPS: int = int(os.getenv("F5_NFE_STEPS", "32"))
F5_CFG_STRENGTH: float = float(os.getenv("F5_CFG_STRENGTH", "2.0"))
F5_SPEED: float = float(os.getenv("F5_SPEED", "1.0"))

MAX_REF_SECONDS: float = float(os.getenv("MAX_REF_SECONDS", "30"))
MAX_GEN_CHARS: int = int(os.getenv("MAX_GEN_CHARS", "1000"))
MAX_UPLOAD_BYTES: int = int(os.getenv("MAX_UPLOAD_BYTES", str(50 * 1024 * 1024)))

GPU_LOCK_NAME: str = os.getenv("GPU_LOCK_NAME", "tts-clone-core")

LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()

ANON_USER: str = "anon"

os.makedirs(STATE_DIR, exist_ok=True)
os.makedirs(REFS_DIR, exist_ok=True)
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(HF_CACHE_DIR, exist_ok=True)
os.environ["HF_HOME"] = HF_CACHE_DIR
