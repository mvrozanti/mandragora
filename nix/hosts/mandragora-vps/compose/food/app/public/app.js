const CATEGORIES = [
  ["canned", "Canned", "🥫"],
  ["frozen", "Frozen", "🧊"],
  ["fresh", "Fresh", "🥬"],
  ["drink", "Drink", "🧃"],
  ["pantry", "Pantry", "🫙"],
  ["other", "Other", "✍️"],
];
const CAT_ORDER = CATEGORIES.map((c) => c[0]);
const CAT_LABEL = Object.fromEntries(CATEGORIES.map((c) => [c[0], c]));

const state = { catalog: [], list: { items: [], updated: null } };
let saveTimer = null;

const $ = (sel) => document.querySelector(sel);
const norm = (s) => (s || "").normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();

function healthColor(h) {
  return { 5: "#3f8f5f", 4: "#78a24a", 3: "#d99a2b", 2: "#d9762b", 1: "#c2503f" }[h] || "#9a9a9a";
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function setSync(status) {
  const el = $("#sync");
  const map = { saving: ["saving…", "warn"], saved: ["synced", "ok"], offline: ["offline", "err"] };
  const [text, cls] = map[status] || ["·", ""];
  el.textContent = text;
  el.className = "sync " + cls;
}

async function loadCatalog() {
  try {
    const res = await fetch("/catalog.json", { cache: "no-store" });
    const data = await res.json();
    state.catalog = data.foods || [];
    localStorage.setItem("food.catalog", JSON.stringify(state.catalog));
  } catch (e) {
    const cached = localStorage.getItem("food.catalog");
    if (cached) state.catalog = JSON.parse(cached);
  }
}

async function loadList() {
  try {
    const res = await fetch("/api/list", { cache: "no-store" });
    const data = await res.json();
    if (data && Array.isArray(data.items)) state.list = data;
  } catch (e) {
    const cached = localStorage.getItem("food.list");
    if (cached) state.list = JSON.parse(cached);
  }
}

function persist() {
  localStorage.setItem("food.list", JSON.stringify(state.list));
  setSync("saving");
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {
    try {
      state.list.updated = new Date().toISOString();
      const res = await fetch("/api/list", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(state.list),
      });
      setSync(res.ok ? "saved" : "offline");
    } catch (e) {
      setSync("offline");
    }
  }, 400);
}

function findItem(id) {
  return state.list.items.find((it) => it.id === id);
}

function buzz() {
  if (navigator.vibrate) navigator.vibrate(8);
}

function addFood(food) {
  const existing = findItem(food.id);
  if (existing) {
    existing.qty += 1;
    existing.checked = false;
  } else {
    state.list.items.push({ id: food.id, name: food.name, category: food.category, qty: 1, checked: false, custom: false });
  }
  buzz();
  persist();
  render();
}

function rememberNew(name) {
  fetch("/api/inbox", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name }),
  }).catch(() => {});
}

function addCustom(rawName) {
  const name = (rawName || "").trim();
  if (!name) return;
  const id = "custom:" + norm(name).replace(/[^a-z0-9]+/g, "-") + ":" + Date.now();
  state.list.items.push({ id, name, category: "other", qty: 1, checked: false, custom: true });
  rememberNew(name);
  buzz();
  persist();
  $("#search").value = "";
  render();
}

function toggle(id) {
  const it = findItem(id);
  if (!it) return;
  it.checked = !it.checked;
  buzz();
  persist();
  render();
}

function setQty(id, delta) {
  const it = findItem(id);
  if (!it) return;
  it.qty = Math.max(1, it.qty + delta);
  persist();
  render();
}

function removeItem(id) {
  state.list.items = state.list.items.filter((it) => it.id !== id);
  persist();
  render();
}

function clearChecked() {
  state.list.items = state.list.items.filter((it) => !it.checked);
  persist();
  render();
}

function itemRow(it) {
  const meta = state.catalog.find((f) => f.id === it.id);
  const row = document.createElement("div");
  row.className = "row" + (it.checked ? " is-checked" : "");
  const price = meta && meta.price ? `<span class="chip">R$ ${escapeHtml(meta.price)}</span>` : "";
  const keeps = meta && meta.keeps ? `<span class="chip subtle">${escapeHtml(meta.keeps)}</span>` : "";
  row.innerHTML = `
    <button class="check" aria-label="toggle">${it.checked ? "✓" : ""}</button>
    <div class="row-main">
      <div class="row-name">${escapeHtml(it.name)}</div>
      <div class="row-meta">${price}${keeps}</div>
    </div>
    <div class="qty">
      <button class="q q-minus" aria-label="less">–</button>
      <span class="q-n">${it.qty}</span>
      <button class="q q-plus" aria-label="more">+</button>
    </div>
    <button class="rm" aria-label="remove">×</button>`;
  row.querySelector(".check").onclick = () => toggle(it.id);
  row.querySelector(".q-minus").onclick = () => setQty(it.id, -1);
  row.querySelector(".q-plus").onclick = () => setQty(it.id, 1);
  row.querySelector(".rm").onclick = () => removeItem(it.id);
  return row;
}

function renderList() {
  const wrap = $("#list");
  const items = state.list.items;
  const remaining = items.filter((it) => !it.checked).length;
  $("#count").textContent = remaining ? String(remaining) : "";
  $("#list-empty").hidden = items.length > 0;
  $("#list-actions").hidden = items.length === 0;
  $("#remaining").textContent = items.length === 0 ? "" : `${remaining} to get · ${items.length - remaining} done`;

  const groups = {};
  for (const it of items) (groups[it.category] || (groups[it.category] = [])).push(it);
  wrap.innerHTML = "";
  for (const cat of CAT_ORDER) {
    const list = groups[cat];
    if (!list || !list.length) continue;
    list.sort((a, b) => Number(a.checked) - Number(b.checked) || a.name.localeCompare(b.name));
    const [, label, emoji] = CAT_LABEL[cat];
    const sec = document.createElement("div");
    sec.className = "group";
    sec.innerHTML = `<h2 class="group-h">${emoji} ${label}</h2>`;
    for (const it of list) sec.appendChild(itemRow(it));
    wrap.appendChild(sec);
  }
}

function foodCard(f, added) {
  const card = document.createElement("button");
  card.className = "card" + (added ? " is-added" : "");
  const dot = `<span class="hdot" style="--c:${healthColor(f.health)}" title="healthiness ${f.health}/5"></span>`;
  const warn = f.trigger ? `<span class="warn" title="trigger food">⚠</span>` : "";
  const price = f.price ? `<span class="chip">R$ ${escapeHtml(f.price)}</span>` : "";
  card.innerHTML = `
    <div class="card-top">${dot}<span class="card-name">${escapeHtml(f.name)}</span>${warn}</div>
    <div class="card-meta"><span class="chip subtle">${escapeHtml(f.keeps)}</span>${price}</div>
    <span class="card-add">${added ? "✓ on list" : "＋ add"}</span>`;
  card.onclick = () => addFood(f);
  return card;
}

function renderCatalog() {
  const wrap = $("#catalog");
  const q = norm($("#search").value);
  const onList = new Set(state.list.items.map((it) => it.id));
  const groups = {};
  for (const f of state.catalog) {
    if (q && !norm(f.name).includes(q)) continue;
    (groups[f.category] || (groups[f.category] = [])).push(f);
  }
  wrap.innerHTML = "";
  let any = false;
  for (const cat of CAT_ORDER) {
    const list = groups[cat];
    if (!list || !list.length) continue;
    any = true;
    const [, label, emoji] = CAT_LABEL[cat];
    const sec = document.createElement("div");
    sec.className = "group";
    sec.innerHTML = `<h2 class="group-h">${emoji} ${label}</h2>`;
    const grid = document.createElement("div");
    grid.className = "grid";
    for (const f of list) grid.appendChild(foodCard(f, onList.has(f.id)));
    sec.appendChild(grid);
    wrap.appendChild(sec);
  }
  const empty = $("#catalog-empty");
  const typed = $("#search").value.trim();
  if (!any) {
    empty.hidden = false;
    empty.innerHTML = typed
      ? `<p class="big">No match in your foods.</p><button class="primary" id="add-typed">Add “${escapeHtml(typed)}”</button>`
      : `<p class="muted">No foods yet.</p>`;
    const btn = $("#add-typed");
    if (btn) btn.onclick = () => addCustom($("#search").value);
  } else {
    empty.hidden = true;
  }
}

function render() {
  renderList();
  renderCatalog();
}

function setView(view) {
  document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("is-active", t.dataset.view === view));
  document.querySelectorAll(".view").forEach((v) => v.classList.toggle("is-active", v.id === "view-" + view));
  window.scrollTo({ top: 0 });
}

function wire() {
  document.querySelectorAll(".tab").forEach((t) => (t.onclick = () => setView(t.dataset.view)));
  document.querySelectorAll("[data-goto]").forEach((b) => (b.onclick = () => setView(b.dataset.goto)));
  $("#clear-checked").onclick = clearChecked;
  $("#add-free").onclick = () => addCustom($("#search").value);
  const search = $("#search");
  search.oninput = () => renderCatalog();
  search.onkeydown = (e) => {
    if (e.key !== "Enter") return;
    const q = norm(search.value);
    const exact = state.catalog.find((f) => norm(f.name) === q);
    if (exact) addFood(exact);
    else addCustom(search.value);
    search.blur();
  };
}

async function init() {
  wire();
  await Promise.all([loadCatalog(), loadList()]);
  setSync("saved");
  render();
}

init();
