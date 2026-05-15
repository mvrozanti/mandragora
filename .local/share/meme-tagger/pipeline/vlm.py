"""Ollama /api/generate caller with image attachment."""
from __future__ import annotations

import base64
import logging

import httpx

log = logging.getLogger(__name__)

PROMPT_VERSION = 2

PROMPT_TEMPLATE = """You are an image-tagging assistant. Be specific and dense — aim for 40-60 distinct tags per image. Produce ONLY a JSON object, no prose. Respect the size caps in each field. Empty arrays/strings where a field doesn't apply:

{{
  "content_type": "meme|photo|screenshot_text|screenshot_app|graph_chart|diagram|art|other",
  "template": "<meme template name (drake, distracted_boyfriend, two_buttons, ...) or empty>",
  "characters": ["<canonical names: pepe, apu, apustaja, wojak, doomer, soyjak, chad, gigachad, drake, spongebob, shrek, ... up to 8>"],
  "text_visible": ["<key text blocks verbatim, up to 12 items; for walls of text take only the most distinctive lines, not exhaustive>"],
  "visual_elements": ["<objects, animals, people, body parts, clothing, props, plants, vehicles, food, etc. 15-25 items. lowercase_underscore.>"],
  "actions": ["<verbs of what's happening; 0-8 items: pointing, crying, drinking, sleeping, holding_phone>"],
  "colors": ["<dominant + accent colors; 3-8 items: red, blue, neon_pink, monochrome, sepia>"],
  "composition": ["<3-6 items: close_up, wide_shot, portrait, two_panel, four_panel, split_screen, top_text_bottom_text>"],
  "style": ["<3-6 items: photo, cartoon, anime, digital_art, sketch, screenshot, low_quality, deep_fried, jpeg_artifacts>"],
  "setting": ["<2-5 items: indoor, outdoor, bedroom, office, street, forest, beach, abstract, plain_white>"],
  "description": "<2-3 sentences max. Concrete: what is in the image.>",
  "context": "<1-2 sentences max. Cultural/situational meaning.>",
  "punchline": "<one short sentence if humorous; empty otherwise>",
  "emotions": ["<3-8 items: smug, sad, angry, copium, wholesome, cringe, based, nostalgic, anxious>"],
  "category": "<one of: tech_humor, political, relationships, gaming, anime, work, finance, crypto, fitness, religion, science, history, music, sports, food, animal_pic, selfie, art, nsfw, ...>",
  "cultural_refs": ["<0-10 named refs: star_wars, 4chan, league_of_legends, bitcoin, the_office, vaporwave>"],
  "extra_tags": ["<10-20 lowercase_underscore tags for later search; include synonyms and mood: dramatic, low_effort, edited, vintage, wholesome_chungus>"]
}}

Rules:
- Total tag array entries across all fields should land around 50 per image. Respect per-field caps.
- For walls of text (poems, equations, paragraphs), text_visible holds only the most distinctive 8-12 lines. Do not transcribe entire passages.
- Name recurring meme characters by canonical names. If unsure but it looks like a known meme character, use your best guess.
- For photos/screenshots/graphs, set template="" and punchline="" but still fill visual_elements/colors/composition/style/setting.
- All tag values lowercase, underscore_separated, no spaces or punctuation inside tags.
- Output strictly valid JSON. No code fences. No commentary outside the JSON object.

OCR pre-pass (use as ground truth if non-empty):
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
        "options": {
            "temperature": temperature,
            "num_predict": 6000,
        },
        "format": "json",
    }
    async with httpx.AsyncClient(timeout=timeout_seconds) as client:
        resp = await client.post(f"{base}/api/generate", json=payload)
        resp.raise_for_status()
        data = resp.json()
    return data.get("response", "")
