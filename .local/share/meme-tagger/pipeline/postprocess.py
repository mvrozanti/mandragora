"""Parse VLM JSON output, normalize tags, populate TaggedImage."""
from __future__ import annotations

import json
import logging
import re
from typing import Any

from . import schema

log = logging.getLogger(__name__)

_FENCE_RE = re.compile(r"^\s*```(?:json)?\s*|\s*```\s*$", re.MULTILINE)
_TRAILING_COMMA_RE = re.compile(r",(\s*[}\]])")


def parse_vlm_json(raw: str) -> dict[str, Any]:
    text = _FENCE_RE.sub("", raw).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    repaired = _TRAILING_COMMA_RE.sub(r"\1", text)
    try:
        return json.loads(repaired)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end > start:
            return json.loads(text[start:end + 1])
        raise


def _as_str_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value] if value.strip() else []
    if isinstance(value, list):
        return [str(x).strip() for x in value if str(x).strip()]
    return [str(value).strip()] if str(value).strip() else []


def build_tagged_image(
    vlm_raw: str,
    ocr_phrases: list[str],
    source: schema.Source,
    model: schema.Model,
) -> schema.TaggedImage:
    parsed = parse_vlm_json(vlm_raw)

    content_type = schema.coerce_content_type(parsed.get("content_type"))
    template = str(parsed.get("template", "") or "").strip()
    characters = _as_str_list(parsed.get("characters"))
    text_visible = _as_str_list(parsed.get("text_visible"))
    description = str(parsed.get("description", "") or "").strip()
    context = str(parsed.get("context", "") or "").strip()
    punchline = str(parsed.get("punchline", "") or "").strip()
    emotions = _as_str_list(parsed.get("emotions"))
    category = str(parsed.get("category", "") or "").strip()
    extra_tags = _as_str_list(parsed.get("extra_tags"))

    merged_text = list(dict.fromkeys([*ocr_phrases, *text_visible]))

    raw_tags: list[str] = []
    raw_tags.append(content_type)
    if category:
        raw_tags.append(category)
    raw_tags.extend(emotions)
    raw_tags.extend(extra_tags)
    if template:
        raw_tags.append(template)
        raw_tags.append(f"tpl:{schema.normalize_tag(template)}")
    for ch in characters:
        norm_ch = schema.normalize_tag(ch)
        if norm_ch:
            raw_tags.append(norm_ch)
            raw_tags.append(f"char:{norm_ch}")
    for phrase in merged_text:
        otag = schema.ocr_phrase_tag(phrase)
        if otag:
            raw_tags.append(otag)

    norm_tags = schema.normalize_tag_list(raw_tags)
    norm_chars = schema.normalize_tag_list(characters)
    norm_emotions = schema.normalize_tag_list(emotions)

    return schema.TaggedImage(
        schema_version=schema.SCHEMA_VERSION,
        tagged_at=schema.now_iso_utc(),
        source=source,
        model=model,
        content_type=content_type,
        template=schema.normalize_tag(template),
        characters=norm_chars,
        text_ocr=merged_text,
        description=description,
        context=context,
        punchline=punchline,
        emotions=norm_emotions,
        category=schema.normalize_tag(category),
        tags=norm_tags,
    )
