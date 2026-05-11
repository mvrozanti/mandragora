#!/usr/bin/env python3
"""Tiny RGB preset web control.

Spawns the openrgb daemon on demand (it's intentionally not auto-started at
boot — see modules/desktop/openrgb.nix comment about the keyleds collision),
then drives presets through the openrgb CLI's client mode.
"""
from __future__ import annotations

import asyncio
import os
import shutil
from aiohttp import web

PRESETS: dict[str, list[str]] = {
    "off":       ["--mode", "static", "--color", "000000"],
    "white":     ["--mode", "static", "--color", "FFFFFF"],
    "red":       ["--mode", "static", "--color", "FF0000"],
    "green":     ["--mode", "static", "--color", "00FF00"],
    "blue":      ["--mode", "static", "--color", "0000FF"],
    "purple":    ["--mode", "static", "--color", "8800FF"],
    "amber":     ["--mode", "static", "--color", "FFA500"],
    "cyan":      ["--mode", "static", "--color", "00FFFF"],
    "breathing": ["--mode", "breathing", "--color", "FF00FF"],
    "rainbow":   ["--mode", "rainbow"],
    "wave":      ["--mode", "rainbow wave"],
}

OPENRGB = shutil.which("openrgb") or "openrgb"
SUDO = shutil.which("sudo") or "/run/wrappers/bin/sudo"
SYSTEMCTL = "/run/current-system/sw/bin/systemctl"


async def ensure_daemon() -> None:
    proc = await asyncio.create_subprocess_exec(
        SUDO, "-n", SYSTEMCTL, "start", "openrgb",
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )
    _, err = await proc.communicate()
    if proc.returncode != 0 and err:
        # surface but don't fail — daemon may already be running
        return None


INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>rgb · mvr.ac</title>
<style>
:root {
  --bg: #050805; --panel: #0a0e0a; --fg: #b8ffc4; --accent: #00ff66;
  --dim: #4a6a4e; --line: #1a2418; --hover: #0f1810;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--fg); font-family: ui-monospace, "Iosevka", monospace;
       min-height: 100vh; padding: 2rem 1.5rem; }
.wrap { max-width: 800px; margin: 0 auto; }
header { display: flex; justify-content: space-between; align-items: baseline;
         border-bottom: 1px solid var(--line); padding-bottom: 1rem; margin-bottom: 2rem; }
h1 { font-size: 1rem; font-weight: normal; }
h1::before { content: "$ "; color: var(--accent); }
.back { color: var(--accent); text-decoration: none; font-size: 0.8rem; }
.back:hover { text-decoration: underline; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 0.6rem; }
.btn { background: var(--panel); border: 1px solid var(--line); color: var(--fg);
       padding: 1rem; font: inherit; cursor: pointer; transition: all 0.12s;
       display: flex; align-items: center; gap: 0.5rem; }
.btn:hover { border-color: var(--accent); background: var(--hover); }
.btn:active { transform: translateY(1px); }
.swatch { width: 1rem; height: 1rem; border: 1px solid var(--line); border-radius: 2px; }
#status { margin-top: 1.5rem; padding: 0.75rem; border: 1px solid var(--line);
          background: var(--panel); font-size: 0.8rem; color: var(--dim); min-height: 2.5rem;
          white-space: pre-wrap; }
#status.ok { color: var(--accent); }
#status.err { color: #ff6b6b; border-color: #ff6b6b; }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>rgb</h1>
    <a class="back" href="https://hub.mvr.ac/">← hub</a>
  </header>
  <div class="grid" id="presets"></div>
  <div id="status">ready</div>
</div>
<script>
const presets = [
  ["off",       "#000000"], ["white",  "#ffffff"], ["red",     "#ff0000"],
  ["green",     "#00ff00"], ["blue",   "#0000ff"], ["purple",  "#8800ff"],
  ["amber",     "#ffa500"], ["cyan",   "#00ffff"], ["breathing","#ff00ff"],
  ["rainbow",   "linear-gradient(90deg, red, orange, yellow, lime, cyan, blue, magenta)"],
  ["wave",      "linear-gradient(90deg, red, orange, yellow, lime, cyan, blue, magenta)"],
];
const grid = document.getElementById("presets");
const status = document.getElementById("status");
for (const [name, col] of presets) {
  const b = document.createElement("button");
  b.className = "btn";
  const sw = document.createElement("span");
  sw.className = "swatch";
  sw.style.background = col;
  b.appendChild(sw);
  const label = document.createElement("span");
  label.textContent = name;
  b.appendChild(label);
  b.addEventListener("click", async () => {
    status.className = "";
    status.textContent = "→ " + name + " ...";
    try {
      const r = await fetch("/p/" + name, { method: "POST" });
      const t = await r.text();
      status.className = r.ok ? "ok" : "err";
      status.textContent = (r.ok ? "✓ " : "✗ ") + name + (t ? "\\n" + t.slice(0, 200) : "");
    } catch (e) {
      status.className = "err";
      status.textContent = "✗ " + e.message;
    }
  });
  grid.appendChild(b);
}
</script>
</body>
</html>
"""


async def apply(request: web.Request) -> web.Response:
    name = request.match_info["name"]
    args = PRESETS.get(name)
    if args is None:
        return web.Response(status=404, text=f"unknown preset: {name}")
    await ensure_daemon()
    proc = await asyncio.create_subprocess_exec(
        OPENRGB, "--noautoconnect", *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    return web.Response(
        text=out.decode(errors="replace")[-400:],
        status=200 if proc.returncode == 0 else 500,
    )


async def index(_: web.Request) -> web.Response:
    return web.Response(text=INDEX_HTML, content_type="text/html")


def main() -> None:
    app = web.Application()
    app.add_routes([
        web.get("/", index),
        web.post("/p/{name}", apply),
    ])
    web.run_app(
        app,
        host=os.environ.get("RGB_HOST", "0.0.0.0"),
        port=int(os.environ.get("RGB_PORT", "6681")),
    )


if __name__ == "__main__":
    main()
