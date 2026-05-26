import logging
import re
import threading
import time
from pathlib import Path

import torch

import config

logger = logging.getLogger(__name__)

PT_BR_REPO = "firstpixel/F5-TTS-pt-br"
PT_BR_FILE = "pt-br/model_last.safetensors"

_engine = None
_engine_lock = threading.Lock()


def _resolve_ckpt() -> str:
    if config.F5_CKPT_FILE:
        return config.F5_CKPT_FILE
    if config.F5_LANG.lower() in ("pt", "pt_br", "pt-br", "ptbr"):
        from huggingface_hub import hf_hub_download
        return hf_hub_download(
            repo_id=PT_BR_REPO, filename=PT_BR_FILE, cache_dir=config.HF_CACHE_DIR,
        )
    return ""


def preprocess_text(text: str) -> str:
    if config.F5_LANG.lower() in ("pt", "pt_br", "pt-br", "ptbr"):
        from num2words import num2words
        text = re.sub(r"\d+", lambda m: num2words(int(m.group()), lang="pt_BR"), text)
        text = text.lower()
    return text


class TTSEngine:
    def __init__(self) -> None:
        self._f5 = None
        self._loaded = False
        self._infer_lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self._loaded

    def load(self) -> None:
        if self._loaded:
            return
        ckpt = _resolve_ckpt()
        logger.info(
            "loading F5-TTS model=%s ckpt=%s lang=%s",
            config.F5_MODEL, ckpt or "<default>", config.F5_LANG or "<auto>",
        )
        t0 = time.time()
        from f5_tts.api import F5TTS
        self._f5 = F5TTS(
            model=config.F5_MODEL,
            ckpt_file=ckpt,
            vocab_file=config.F5_VOCAB_FILE,
            hf_cache_dir=config.HF_CACHE_DIR,
        )
        self._loaded = True
        logger.info("F5-TTS loaded in %.1fs", time.time() - t0)

    def infer(
        self,
        ref_audio: str | Path,
        gen_text: str,
        out_path: str | Path,
        ref_text: str = "",
        seed: int = -1,
    ) -> Path:
        if not self._loaded:
            self.load()
        out_path = Path(out_path)
        out_path.parent.mkdir(parents=True, exist_ok=True)

        gen_text = preprocess_text(gen_text)
        if ref_text:
            ref_text = preprocess_text(ref_text)

        with self._infer_lock:
            try:
                t0 = time.time()
                wav, sr, _ = self._f5.infer(
                    ref_file=str(ref_audio),
                    ref_text=ref_text,
                    gen_text=gen_text,
                    nfe_step=config.F5_NFE_STEPS,
                    cfg_strength=config.F5_CFG_STRENGTH,
                    speed=config.F5_SPEED,
                    file_wave=str(out_path),
                    seed=seed,
                )
                logger.info(
                    "synthesized %s (%.1fs, sr=%d) from ref=%s",
                    out_path.name, time.time() - t0, sr, Path(ref_audio).name,
                )
                return out_path
            finally:
                torch.cuda.empty_cache()


def get_engine() -> TTSEngine:
    global _engine
    if _engine is not None:
        return _engine
    with _engine_lock:
        if _engine is None:
            _engine = TTSEngine()
        return _engine
