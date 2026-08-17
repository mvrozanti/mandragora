import { fmtTime } from "./draw.js";

const tiles = document.getElementById("tiles");
const empty = document.getElementById("empty");

function esc(s) {
  return String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function sceneText(s) {
  return Array.isArray(s) ? s[0] : s;
}

function valGlyph(v) {
  if (v == null || !isFinite(v)) return "·";
  if (v > 0.05) return "+";
  if (v < -0.05) return "−";
  return "0";
}

function tile(tr) {
  const a = document.createElement("a");
  a.className = "tile";
  a.href = "track.html?t=" + encodeURIComponent(tr.slug);
  const scenes = (tr.scenes || []).map(sceneText).join(" · ");
  const bpm = tr.bpm ? Math.round(tr.bpm * 10) / 10 : null;
  a.innerHTML =
    '<span class="tdisc"><img src="' + esc(tr.cover || "") + '" alt="" loading="lazy" decoding="async"></span>' +
    '<span class="tmeta">' +
    '<span class="tartist">' + esc(tr.artist || "") + "</span>" +
    '<span class="ttitle">' + esc(tr.title || tr.slug) + "</span>" +
    (scenes ? '<span class="tscenes">' + esc(scenes) + "</span>" : "") +
    '<span class="chips">' +
    (bpm ? '<span class="chip"><b>' + bpm + "</b><i>bpm</i></span>" : "") +
    (tr.key ? '<span class="chip"><b>' + esc(tr.key) + "</b></span>" : "") +
    '<span class="chip"><b>' + fmtTime(tr.duration) + "</b></span>" +
    '<span class="chip" title="valence ' + esc(tr.valence) + " · arousal " + esc(tr.arousal) + '"><i>val</i><b>' + valGlyph(tr.valence) + "</b></span>" +
    "</span></span>";
  return a;
}

async function init() {
  let manifest;
  try {
    const r = await fetch("tracks/manifest.json");
    if (!r.ok) throw new Error(String(r.status));
    manifest = await r.json();
  } catch (e) {
    empty.hidden = false;
    empty.textContent = "the catalogue is unavailable";
    return;
  }
  const tracks = manifest.tracks || [];
  if (!tracks.length) {
    empty.hidden = false;
    return;
  }
  if (tracks.length === 1) tiles.classList.add("solo");
  for (const tr of tracks) tiles.appendChild(tile(tr));
}

init();
