#!/usr/bin/env python3
"""Minimal web UI for im-gen's FluxEngine. Single prompt → image.

Reuses the FluxEngine class from bot.py (same venv, same gpu_lock).
Lazy-loads the model on first /generate request, then stays warm.
Note: if the Telegram bot is also running, both will hold ~6GB VRAM
each with cpu_offload, totalling ~12GB on the 16GB RTX 5070 Ti.
gpu_lock arbitrates which one runs at a time but doesn't prevent
simultaneous model presence. Restart whichever is idle if you need
the other to do tight memory work.
"""
from __future__ import annotations

import asyncio
import logging
import os
import sys
import time
from pathlib import Path

# Reach into bot.py from a sibling location.
IM_GEN_DIR = Path(os.environ.get("IM_GEN_DIR", "/home/m/Projects/im-gen"))
sys.path.insert(0, str(IM_GEN_DIR))

from aiohttp import web
from bot import FluxEngine  # type: ignore

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("gen-web")

engine = FluxEngine()
load_lock = asyncio.Lock()


async def ensure_loaded() -> None:
    if engine.pipe is not None:
        return
    async with load_lock:
        if engine.pipe is not None:
            return
        await engine.load()


INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>image gen · mvr.ac</title>
<style>
:root { --bg:#050805; --panel:#0a0e0a; --fg:#b8ffc4; --accent:#00ff66; --dim:#4a6a4e; --line:#1a2418; --hover:#0f1810; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--fg); font-family: ui-monospace, "Iosevka", monospace; min-height: 100vh; padding: 2rem 1.5rem; }
.wrap { max-width: 1000px; margin: 0 auto; }
header { display: flex; justify-content: space-between; align-items: baseline; border-bottom: 1px solid var(--line); padding-bottom: 1rem; margin-bottom: 2rem; }
h1 { font-size: 1rem; font-weight: normal; }
h1::before { content: "$ "; color: var(--accent); }
.back { color: var(--accent); text-decoration: none; font-size: 0.8rem; }
form { display: flex; flex-direction: column; gap: 0.75rem; }
textarea { background: var(--panel); border: 1px solid var(--line); color: var(--fg); font: inherit; padding: 0.9rem; resize: vertical; min-height: 90px; outline: none; }
textarea:focus { border-color: var(--accent); }
.row { display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
label { color: var(--dim); font-size: 0.75rem; }
input[type=number] { background: var(--panel); border: 1px solid var(--line); color: var(--fg); padding: 0.4rem 0.5rem; font: inherit; width: 6rem; }
button { background: var(--panel); border: 1px solid var(--accent); color: var(--accent); padding: 0.65rem 1.2rem; font: inherit; cursor: pointer; transition: all 0.12s; }
button:hover:not(:disabled) { background: var(--accent); color: var(--bg); }
button:disabled { opacity: 0.45; cursor: wait; }
#status { margin-top: 1rem; color: var(--dim); font-size: 0.8rem; min-height: 1.2em; white-space: pre-wrap; }
#status.ok { color: var(--accent); }
#status.err { color: #ff6b6b; }
#result { margin-top: 1.5rem; }
#result img { max-width: 100%; height: auto; border: 1px solid var(--line); }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>image gen</h1>
    <a class="back" href="https://hub.mvr.ac/">← hub</a>
  </header>
  <form id="f">
    <textarea id="prompt" placeholder="prompt: a moss-covered statue in a quiet forest, soft morning light" required></textarea>
    <div class="row">
      <label>seed <input id="seed" type="number" placeholder="random" min="0" max="2147483647"></label>
      <button id="go" type="submit">generate</button>
    </div>
  </form>
  <div id="status"></div>
  <div id="result"></div>
</div>
<script>
const f = document.getElementById("f");
const go = document.getElementById("go");
const promptEl = document.getElementById("prompt");
const seedEl = document.getElementById("seed");
const statusEl = document.getElementById("status");
const result = document.getElementById("result");
f.addEventListener("submit", async (e) => {
  e.preventDefault();
  const prompt = promptEl.value.trim();
  if (!prompt) return;
  const seed = seedEl.value ? Number(seedEl.value) : null;
  go.disabled = true;
  statusEl.className = "";
  statusEl.textContent = "loading model + generating (first run takes ~60s)...";
  const t0 = Date.now();
  const tick = setInterval(() => {
    statusEl.textContent = "generating ... " + ((Date.now() - t0) / 1000).toFixed(1) + "s";
  }, 500);
  try {
    const r = await fetch("/generate", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt, seed }),
    });
    clearInterval(tick);
    if (!r.ok) {
      statusEl.className = "err";
      statusEl.textContent = "✗ " + r.status + " " + (await r.text()).slice(0, 400);
      return;
    }
    const blob = await r.blob();
    const url = URL.createObjectURL(blob);
    const img = document.createElement("img");
    img.src = url;
    result.innerHTML = "";
    result.appendChild(img);
    statusEl.className = "ok";
    statusEl.textContent = "✓ " + ((Date.now() - t0) / 1000).toFixed(1) + "s";
  } catch (err) {
    clearInterval(tick);
    statusEl.className = "err";
    statusEl.textContent = "✗ " + err.message;
  } finally {
    go.disabled = false;
  }
});
</script>
</body>
</html>
"""


async def index(_: web.Request) -> web.Response:
    return web.Response(text=INDEX_HTML, content_type="text/html")


async def generate(request: web.Request) -> web.Response:
    try:
        data = await request.json()
    except Exception:
        return web.json_response({"error": "invalid json"}, status=400)
    prompt = (data.get("prompt") or "").strip()
    if not prompt:
        return web.json_response({"error": "empty prompt"}, status=400)
    seed_raw = data.get("seed")
    seed = int(seed_raw) if seed_raw is not None and seed_raw != "" else None

    t0 = time.time()
    await ensure_loaded()
    try:
        path = await engine.generate(prompt, seed=seed)
    except Exception as e:
        log.exception("generation failed")
        return web.json_response({"error": str(e)}, status=500)
    log.info("generated %s in %.1fs (prompt=%r)", path, time.time() - t0, prompt[:80])
    img_path = Path(path)
    if not img_path.exists():
        return web.json_response({"error": "image not on disk"}, status=500)
    return web.Response(body=img_path.read_bytes(), content_type="image/png")


def main() -> None:
    app = web.Application(client_max_size=8 * 1024 * 1024)
    app.add_routes([
        web.get("/", index),
        web.post("/generate", generate),
    ])
    web.run_app(
        app,
        host=os.environ.get("GEN_HOST", "0.0.0.0"),
        port=int(os.environ.get("GEN_PORT", "6682")),
    )


if __name__ == "__main__":
    main()
