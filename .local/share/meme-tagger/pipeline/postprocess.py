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
        pass
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end > start:
        try:
            return json.loads(text[start:end + 1])
        except json.JSONDecodeError:
            pass
    return _salvage_truncated(text[start:] if start != -1 else text)


def _salvage_truncated(text: str) -> dict[str, Any]:
    stack: list[str] = []
    in_string = False
    escape = False
    safe_end = 0
    last_unsafe_open = -1
    for i, ch in enumerate(text):
        if escape:
            escape = False
            continue
        if in_string:
            if ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
                if stack and stack[-1] == "[":
                    safe_end = i + 1
            continue
        if ch == '"':
            in_string = True
            last_unsafe_open = i
            continue
        if ch in "{[":
            stack.append(ch)
            continue
        if ch in "}]":
            if stack:
                stack.pop()
            safe_end = i + 1
            continue
        if ch == ",":
            safe_end = i
            continue

    if safe_end <= 0:
        raise json.JSONDecodeError("nothing salvageable", text, 0)

    repaired = text[:safe_end].rstrip().rstrip(",")
    depth_obj = repaired.count("{") - repaired.count("}")
    depth_arr = 0
    rebuild_stack: list[str] = []
    in_s = False
    esc = False
    for ch in repaired:
        if esc:
            esc = False
            continue
        if in_s:
            if ch == "\\":
                esc = True
            elif ch == '"':
                in_s = False
            continue
        if ch == '"':
            in_s = True
        elif ch in "{[":
            rebuild_stack.append(ch)
        elif ch in "}]":
            if rebuild_stack:
                rebuild_stack.pop()
    closers = "".join("}" if c == "{" else "]" for c in reversed(rebuild_stack))
    repaired += closers
    return json.loads(repaired)


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
    visual_elements = _as_str_list(parsed.get("visual_elements"))
    actions = _as_str_list(parsed.get("actions"))
    colors = _as_str_list(parsed.get("colors"))
    composition = _as_str_list(parsed.get("composition"))
    style = _as_str_list(parsed.get("style"))
    setting = _as_str_list(parsed.get("setting"))
    cultural_refs = _as_str_list(parsed.get("cultural_refs"))
    extra_tags = _as_str_list(parsed.get("extra_tags"))

    merged_text = list(dict.fromkeys([*ocr_phrases, *text_visible]))

    raw_tags: list[str] = []
    raw_tags.append(content_type)
    if category:
        raw_tags.append(category)
    raw_tags.extend(emotions)
    raw_tags.extend(visual_elements)
    raw_tags.extend(actions)
    raw_tags.extend(composition)
    raw_tags.extend(style)
    raw_tags.extend(setting)
    raw_tags.extend(extra_tags)
    for c in colors:
        norm_c = schema.normalize_tag(c)
        if norm_c:
            raw_tags.append(norm_c)
            raw_tags.append(f"color:{norm_c}")
    for ref in cultural_refs:
        norm_r = schema.normalize_tag(ref)
        if norm_r:
            raw_tags.append(norm_r)
            raw_tags.append(f"ref:{norm_r}")
    if template:
        norm_t = schema.normalize_tag(template)
        raw_tags.append(norm_t)
        raw_tags.append(f"tpl:{norm_t}")
    for ch in characters:
        norm_ch = schema.normalize_tag(ch)
        if norm_ch:
            raw_tags.append(norm_ch)
            raw_tags.append(f"char:{norm_ch}")
    for phrase in merged_text:
        otag = schema.ocr_phrase_tag(phrase)
        if otag:
            raw_tags.append(otag)

    return schema.TaggedImage(
        schema_version=schema.SCHEMA_VERSION,
        tagged_at=schema.now_iso_utc(),
        source=source,
        model=model,
        content_type=content_type,
        template=schema.normalize_tag(template),
        characters=schema.normalize_tag_list(characters),
        text_ocr=merged_text,
        description=description,
        context=context,
        punchline=punchline,
        emotions=schema.normalize_tag_list(emotions),
        category=schema.normalize_tag(category),
        visual_elements=schema.normalize_tag_list(visual_elements),
        actions=schema.normalize_tag_list(actions),
        colors=schema.normalize_tag_list(colors),
        composition=schema.normalize_tag_list(composition),
        style=schema.normalize_tag_list(style),
        setting=schema.normalize_tag_list(setting),
        cultural_refs=schema.normalize_tag_list(cultural_refs),
        tags=schema.normalize_tag_list(raw_tags),
    )
