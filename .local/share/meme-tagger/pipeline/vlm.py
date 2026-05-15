"""Ollama /api/generate caller with image attachment."""
from __future__ import annotations

import base64
import logging

import httpx

log = logging.getLogger(__name__)

PROMPT_VERSION = 2

PROMPT_TEMPLATE = """You are an exhaustive image-tagging assistant. Be obsessively thorough: every object, every visible detail, every cultural reference, every color, every emotion. Aim for 40+ distinct tags per image even for simple photos. Produce ONLY a JSON object, no prose, matching this schema (empty arrays/strings where a field doesn't apply):

{{
  "content_type": "meme|photo|screenshot_text|screenshot_app|graph_chart|diagram|art|other",
  "template": "<canonical meme template name (drake, distracted_boyfriend, two_buttons, etc.) or empty>",
  "characters": ["<every named character present: pepe, apu, apustaja, wojak, doomer, soyjak, chad, gigachad, drake, spongebob, shrek, etc. Use canonical lowercase names.>"],
  "text_visible": ["<each distinct text block as seen, verbatim, preserving line order>"],
  "visual_elements": ["<EXHAUSTIVE: every object, animal, person, body part, clothing item, accessory, prop, plant, vehicle, building, food, weapon, etc. Aim 15-30 items. Examples: cat, hand, sword, table, microphone, ufo, sunglasses, beard, tear, smoke, frog, hat. Lowercase, underscore_separated.>"],
  "actions": ["<verbs for what's happening: pointing, crying, screaming, drinking, fighting, sleeping, holding_phone, etc. 0-10 items.>"],
  "colors": ["<dominant + accent colors: red, blue, green, neon_pink, monochrome, grayscale, sepia, etc. 3-10 items.>"],
  "composition": ["<framing/layout: close_up, wide_shot, portrait, landscape, square, vertical, two_panel, four_panel, split_screen, top_text_bottom_text, zoomed_in, full_body, cropped, centered>"],
  "style": ["<medium/style: photo, cartoon, anime, digital_art, sketch, screenshot, render_3d, oil_painting, pixel_art, low_quality, deep_fried, jpeg_artifacts, watermarked>"],
  "setting": ["<location/scene: indoor, outdoor, bedroom, office, street, forest, beach, sky, abstract, plain_white, plain_black, void, party, classroom>"],
  "description": "<3-5 sentences: factually what is depicted; mention key visual elements explicitly>",
  "context": "<1-3 sentences: cultural/situational meaning, what the meme is doing, what audience it targets>",
  "punchline": "<1-2 sentences: the joke, irony, or message if humorous; empty otherwise>",
  "emotions": ["<emotional tone words; both depicted and intended. 3-10 items. Examples: smug, sad, angry, copium, schadenfreude, wholesome, cringe, based, nostalgic, anxious>"],
  "category": "<single domain label: tech_humor, political, relationships, gaming, anime, work, finance, crypto, fitness, religion, science, history, music, sports, food, animal_pic, selfie, art, nsfw, etc.>",
  "cultural_refs": ["<named references: brands, fandoms, games, shows, songs, websites, subcultures, historical events. e.g. star_wars, 4chan, league_of_legends, doom_eternal, bitcoin, gigachad, the_office, vaporwave. 0-15 items.>"],
  "extra_tags": ["<15-30 free-form lowercase underscore tags useful for later search; redundancy is GOOD. Include synonyms, related concepts, mood descriptors, visual qualities. e.g. dramatic, low_effort, edited, photoshop, ai_generated, vintage, wholesome_chungus>"]
}}

Rules:
- Total tags across all array fields should yield 40+ for almost any image. When in doubt, include more, not fewer.
- If the image contains text, capture it verbatim in text_visible, preserving line order. Don't summarize.
- Name recurring meme characters by their canonical names. If unsure but it looks like a known meme character, use your best guess.
- For photos/screenshots/graphs, set template="" and punchline="" but still fill visual_elements/colors/composition/style/setting exhaustively.
- All tag values are lowercase, underscore_separated, no spaces or punctuation inside tags.
- Output strictly valid JSON. No code fences. No commentary outside the JSON object.

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
