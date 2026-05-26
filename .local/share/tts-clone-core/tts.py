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

SUPPORTED_LANGS = ("en", "pt")


def normalize_lang(lang: str | None) -> str:
    if not lang:
        return "en"
    l = lang.strip().lower().replace("-", "_")
    if l in ("pt", "pt_br", "ptbr"):
        return "pt"
    return "en"


def preprocess_text(text: str, lang: str) -> str:
    if lang == "pt":
        from num2words import num2words
        text = re.sub(r"\d+", lambda m: num2words(int(m.group()), lang="pt_BR"), text)
        text = text.lower()
    return text


def _resolve_ckpt(lang: str) -> str:
    if lang == "pt":
        from huggingface_hub import hf_hub_download
        return hf_hub_download(
            repo_id=PT_BR_REPO, filename=PT_BR_FILE, cache_dir=config.HF_CACHE_DIR,
        )
    return ""


class TTSEngine:
    def __init__(self) -> None:
        self._models: dict[str, object] = {}
        self._load_lock = threading.Lock()
        self._infer_lock = threading.Lock()

    def is_loaded(self, lang: str) -> bool:
        return normalize_lang(lang) in self._models

    @property
    def loaded_langs(self) -> list[str]:
        return sorted(self._models.keys())

    def _get_or_load(self, lang: str):
        lang = normalize_lang(lang)
        if lang in self._models:
            return self._models[lang]
        with self._load_lock:
            if lang in self._models:
                return self._models[lang]
            ckpt = _resolve_ckpt(lang)
            model_name = "F5TTS_v1_Base"
            logger.info(
                "loading F5-TTS lang=%s model=%s ckpt=%s",
                lang, model_name, ckpt or "<default>",
            )
            t0 = time.time()
            from f5_tts.api import F5TTS
            f5 = F5TTS(
                model=model_name,
                ckpt_file=ckpt,
                vocab_file=config.F5_VOCAB_FILE,
                hf_cache_dir=config.HF_CACHE_DIR,
            )
            self._models[lang] = f5
            logger.info("F5-TTS lang=%s loaded in %.1fs", lang, time.time() - t0)
            return f5

    def load(self, lang: str = "en") -> None:
        self._get_or_load(lang)

    def infer(
        self,
        ref_audio: str | Path,
        gen_text: str,
        out_path: str | Path,
        lang: str = "en",
        ref_text: str = "",
        seed: int = -1,
    ) -> Path:
        lang = normalize_lang(lang)
        f5 = self._get_or_load(lang)
        out_path = Path(out_path)
        out_path.parent.mkdir(parents=True, exist_ok=True)

        gen_text = preprocess_text(gen_text, lang)
        if ref_text:
            ref_text = preprocess_text(ref_text, lang)

        with self._infer_lock:
            try:
                t0 = time.time()
                wav, sr, _ = f5.infer(
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
                    "synthesized %s lang=%s (%.1fs, sr=%d) from ref=%s",
                    out_path.name, lang, time.time() - t0, sr, Path(ref_audio).name,
                )
                return out_path
            finally:
                torch.cuda.empty_cache()


_engine: TTSEngine | None = None
_engine_lock = threading.Lock()


def get_engine() -> TTSEngine:
    global _engine
    if _engine is not None:
        return _engine
    with _engine_lock:
        if _engine is None:
            _engine = TTSEngine()
        return _engine
