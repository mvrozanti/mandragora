"""RapidOCR pre-pass. CPU-only. Loaded lazily to keep import-time cheap."""
from __future__ import annotations

import logging
from pathlib import Path

log = logging.getLogger(__name__)

_engine = None
_version = "rapidocr-onnxruntime"


def _get_engine():
    global _engine, _version
    if _engine is None:
        from rapidocr_onnxruntime import RapidOCR
        try:
            from importlib.metadata import version as _v
            _version = f"rapidocr-onnxruntime-{_v('rapidocr-onnxruntime')}"
        except Exception:
            pass
        _engine = RapidOCR()
    return _engine


def version_string() -> str:
    _get_engine()
    return _version


def extract(path: Path) -> list[str]:
    try:
        engine = _get_engine()
    except Exception as exc:
        log.warning("RapidOCR unavailable, skipping pre-pass: %s", exc)
        return []
    try:
        result, _elapsed = engine(str(path))
    except Exception as exc:
        log.warning("RapidOCR failed on %s: %s", path, exc)
        return []
    if not result:
        return []
    phrases: list[str] = []
    for entry in result:
        if not entry or len(entry) < 2:
            continue
        text = (entry[1] or "").strip()
        if text:
            phrases.append(text)
    return phrases


def render_for_prompt(phrases: list[str]) -> str:
    if not phrases:
        return ""
    return "\n".join(phrases)
