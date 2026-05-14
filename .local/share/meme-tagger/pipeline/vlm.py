"""Ollama /api/generate caller with image attachment."""
from __future__ import annotations

import base64
import logging

import httpx

log = logging.getLogger(__name__)

PROMPT_VERSION = 1

PROMPT_TEMPLATE = """You are a precise image-tagging assistant. Analyze the image and produce ONLY a JSON object, no prose, matching this schema (use empty strings/arrays where a field does not apply):

{{
  "content_type": "meme|photo|screenshot_text|screenshot_app|graph_chart|diagram|art|other",
  "template": "<canonical meme template name or empty>",
  "characters": ["<character names present: pepe, apu, wojak, drake, chad, gigachad, soyjak, doomer, etc.>"],
  "text_visible": ["<each distinct text block as seen in the image>"],
  "description": "<2-4 sentences: what is depicted, objectively>",
  "context": "<1-2 sentences: cultural/situational meaning if any>",
  "punchline": "<1 sentence: the joke or message, if the image is humorous>",
  "emotions": ["<emotional tone words>"],
  "category": "<single domain label: tech_humor, political, relationships, gaming, anime, work, finance, etc.>",
  "extra_tags": ["<5-15 lowercase underscore-separated keywords useful for later search>"]
}}

Constraints:
- If the image contains text, capture it verbatim in text_visible, preserving line order.
- Name recurring meme characters explicitly when present (pepe, apu, wojak variants, chad, drake, etc.).
- For photos/screenshots/graphs, set template="" and punchline="".
- Output strictly valid JSON. No code fences. No commentary.

OCR pre-pass (use as ground truth if non-empty, otherwise rely on your own reading):
<<<OCR>>>
{ocr_text}
<<<END OCR>>>
"""


def render_prompt(ocr_text: str) -> str:
    return PROMPT_TEMPLATE.format(ocr_text=ocr_text or "(no OCR text)")


async def call(
    base_url: str,
    model: str,
    image_bytes: bytes,
    prompt: str,
    temperature: float,
    timeout_seconds: float,
) -> str:
    base = base_url.rstrip("/")
    payload = {
        "model": model,
        "prompt": prompt,
        "images": [base64.b64encode(image_bytes).decode("ascii")],
        "stream": False,
        "options": {"temperature": temperature},
        "format": "json",
    }
    async with httpx.AsyncClient(timeout=timeout_seconds) as client:
        resp = await client.post(f"{base}/api/generate", json=payload)
        resp.raise_for_status()
        data = resp.json()
    return data.get("response", "")
