"""Sidecar JSON schema (version 1). Always emits every field."""
from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 2

VALID_CONTENT_TYPES = (
    "meme", "photo", "screenshot_text", "screenshot_app",
    "graph_chart", "diagram", "art", "other",
)


@dataclass
class Source:
    path: str = ""
    sha256: str = ""
    mtime: int = 0
    size_bytes: int = 0
    format: str = ""
    width: int = 0
    height: int = 0
    frames: int = 1


@dataclass
class Model:
    vlm: str = ""
    ocr: str = ""
    prompt_version: int = 1


@dataclass
class TaggedImage:
    schema_version: int = SCHEMA_VERSION
    tagged_at: str = ""
    source: Source = field(default_factory=Source)
    model: Model = field(default_factory=Model)
    content_type: str = "other"
    template: str = ""
    characters: list[str] = field(default_factory=list)
    text_ocr: list[str] = field(default_factory=list)
    description: str = ""
    context: str = ""
    punchline: str = ""
    emotions: list[str] = field(default_factory=list)
    category: str = ""
    visual_elements: list[str] = field(default_factory=list)
    actions: list[str] = field(default_factory=list)
    colors: list[str] = field(default_factory=list)
    composition: list[str] = field(default_factory=list)
    style: list[str] = field(default_factory=list)
    setting: list[str] = field(default_factory=list)
    cultural_refs: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2, ensure_ascii=False, sort_keys=False)

    @classmethod
    def from_json_file(cls, path: Path) -> "TaggedImage":
        data = json.loads(path.read_text())
        src = Source(**data.pop("source", {}))
        mdl = Model(**data.pop("model", {}))
        return cls(source=src, model=mdl, **data)


_NORMALIZE_RE = re.compile(r"[^a-z0-9:]+")
_STOPWORDS = frozenset({
    "a", "an", "the", "and", "or", "but", "is", "are", "was", "were", "be",
    "been", "being", "to", "of", "in", "on", "at", "by", "for", "with",
    "as", "it", "its", "this", "that", "these", "those", "i", "you", "he",
    "she", "we", "they", "me", "him", "her", "us", "them", "my", "your",
    "his", "our", "their", "what", "which", "who", "whom", "do", "does",
    "did", "have", "has", "had", "if", "then", "than", "so", "not", "no",
    "yes", "can", "will", "would", "should", "could", "may", "might",
})


def normalize_tag(raw: str) -> str:
    s = _NORMALIZE_RE.sub("_", raw.lower()).strip("_")
    return s


MAX_TAG_LEN = 48
MAX_TAGS = 120


def normalize_tag_list(items: list[str], *, cap: int | None = None) -> list[str]:
    seen: dict[str, None] = {}
    for item in items:
        norm = normalize_tag(item)
        if not norm or norm in seen:
            continue
        if len(norm) > MAX_TAG_LEN:
            continue
        if norm.count("_") > 6:
            continue
        seen[norm] = None
        if cap is not None and len(seen) >= cap:
            break
    return list(seen.keys())


def now_iso_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def coerce_content_type(value: Any) -> str:
    s = str(value or "").strip().lower()
    if s in VALID_CONTENT_TYPES:
        return s
    return "other"


def ocr_phrase_tag(phrase: str) -> str:
    body = normalize_tag(phrase).replace(":", "_")
    words = [w for w in body.split("_") if w and w not in _STOPWORDS]
    if not words:
        return ""
    return "ocr:" + "_".join(words[:6])
