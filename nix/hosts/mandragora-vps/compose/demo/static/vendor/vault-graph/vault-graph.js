/**
 * vault-graph — force-directed canvas viewer for an Obsidian-style markdown vault.
 *
 * Public API:
 *   const vg = VaultGraph.create({
 *     rootEl: document.body,                     // optional, defaults to <body>
 *     brand: {
 *       title: 'my vault',                       // HUD title
 *       blurbHTML: 'Click a node to read…',      // HUD blurb (HTML)
 *       footerHTML: 'my-vault',                  // bottom-right footer (HTML)
 *     },
 *     fetchGraph: () => Promise<{nodes, links}>, // required — {id, label, group, path, deg}
 *     fetchNote:  (path) => Promise<string>,     // required — raw markdown
 *     hudExtras?:  (hud) => void,                // append custom DOM to #hud
 *     onPanelOpen?: (panel) => void,             // decorate the reader panel
 *     onPanelClose?: () => void,
 *     layoutCacheKey?: 'vault-graph-layout-v1',  // bump to invalidate localStorage layout
 *   });
 *
 * `panel` passed to onPanelOpen:
 *   {
 *     node,                       // the graph node (id, label, group, path, deg, …)
 *     raw,                        // raw markdown text
 *     bodyEl, actionsEl, extrasEl,
 *     addAction(label, onClick, opts) => HTMLButtonElement,
 *     setBodyHTML(html),
 *     setBodyMarkdown(md),
 *     restoreBody(),              // re-render the original markdown
 *     setExtras(htmlOrEl),
 *     close(),
 *     panTo(k?),
 *   }
 *
 * Returned instance:
 *   vg.openNote(id)
 *   vg.reload()                   // re-fetch graph + redraw
 *   vg.destroy()
 *   vg.data                       // {nodes, links}
 *
 * Requires globals: d3 (>= 7), marked (>= 4).
 */
(function (root) {
  if (root.VaultGraph) return;

  const FRONTMATTER = /^---\r?\n[\s\S]*?\r?\n---\r?\n?/;
  const WIKILINK_MD = /\[\[([^\]\n|#]+)(#[^\]\n|]+)?(?:\|([^\]\n]+))?\]\]/g;

  function escapeHTML(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function injectScaffold(mount, brand) {
    mount.insertAdjacentHTML("beforeend", `
      <canvas id="c" class="vg-canvas"></canvas>
      <div id="hud">
        <header class="row"><b>${escapeHTML(brand.title || "vault-graph")}</b><span id="counts"></span></header>
        <p class="blurb">${brand.blurbHTML || ""}</p>
        <input id="search" placeholder="search…" autocomplete="off" aria-label="Search notes">
        <div id="hud-categories" role="button" tabindex="0" aria-label="Toggle categories">categories</div>
        <nav id="legend" aria-label="Note categories"></nav>
      </div>
      <footer id="site-footer">${brand.footerHTML || ""}</footer>
      <div id="tooltip"></div>
      <aside id="reader" aria-hidden="true">
        <header>
          <div style="flex:1; min-width:0;">
            <div class="crumb" id="reader-crumb"></div>
            <div class="title" id="reader-title"></div>
          </div>
          <div class="actions" id="reader-actions">
            <button class="vg-close" type="button" id="reader-close" title="Close (Esc)">×</button>
          </div>
        </header>
        <div class="body" id="reader-body"></div>
        <div id="reader-extras"></div>
      </aside>
    `);
  }

  async function create(opts) {
    if (!opts || typeof opts.fetchGraph !== "function" || typeof opts.fetchNote !== "function") {
      throw new Error("VaultGraph.create: fetchGraph + fetchNote are required");
    }
    const mount = opts.rootEl || document.body;
    const brand = opts.brand || {};
    injectScaffold(mount, brand);

    if (typeof opts.hudExtras === "function") {
      opts.hudExtras(mount.querySelector("#hud"));
    }

    const data = await opts.fetchGraph();
    return wire(mount, data, opts);
  }

  function wire(mount, data, opts) {
    const canvas = mount.querySelector("#c");
    const ctx = canvas.getContext("2d");
    const tooltip = mount.querySelector("#tooltip");
    const COARSE = matchMedia("(pointer: coarse)").matches;
    const dpr = Math.min(window.devicePixelRatio || 1, COARSE ? 1.5 : 2);

    let W = 0, H = 0;
    function resize() {
      W = window.innerWidth; H = window.innerHeight;
      canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
      canvas.style.width = W + "px"; canvas.style.height = H + "px";
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    resize();
    window.addEventListener("resize", resize);

    const groups = Array.from(new Set(data.nodes.map(n => n.group))).sort();
    const palette = [
      "#00ff66", "#cfa64a", "#7fcf8a", "#cf6a7a", "#c79ad0",
      "#d8c277", "#5fb89e", "#cf9a5a", "#9ec77a", "#7ac28a",
      "#cf6a6a", "#a78aaa", "#a7c98a", "#7ac0a0", "#c08a6a",
    ];
    const groupColor = {};
    groups.forEach((g, i) => groupColor[g] = palette[i % palette.length]);
    groupColor["_unresolved"] = "#4a4f5a";

    mount.querySelector("#counts").textContent =
      `${data.nodes.length} notes · ${data.links.length} links`;
    const legend = mount.querySelector("#legend");
    const groupRows = new Map();
    const nodesByGroup = new Map();
    for (const g of groups) nodesByGroup.set(g, new Set());
    for (const n of data.nodes) nodesByGroup.get(n.group).add(n.id);

    // Group-highlight state machine.
    // - stuckGroup: pinned by click (sticky until toggled or void-click).
    // - hoverGroup: temporary preview from mousing over a row.
    // - hover (node):  separate concern; node hover wins over group state.
    // Rendering reads both and reconciles every transition through renderGroup.
    let stuckGroup = null;
    let hoverGroup = null;

    function renderGroup() {
      const effective = hoverGroup || stuckGroup;
      for (const [k, row] of groupRows) {
        row.classList.toggle("hot", k === effective);
      }
      if (hover) return;  // node hover keeps its own highlight set
      if (!effective) {
        highlight = new Set();
        highlightLinks = new Set();
      } else {
        const ids = nodesByGroup.get(effective);
        highlight = new Set(ids);
        highlightLinks = new Set();
        for (const l of data.links) {
          const s = l.source.id || l.source;
          const t = l.target.id || l.target;
          if (ids.has(s) && ids.has(t)) highlightLinks.add(l);
        }
      }
      markDirty();
    }

    function unstickGroup() {
      if (!stuckGroup) return false;
      stuckGroup = null;
      renderGroup();
      return true;
    }

    for (const g of groups) {
      const row = document.createElement("div");
      row.className = "row";
      const sw = document.createElement("div");
      sw.className = "sw"; sw.style.background = groupColor[g];
      const lb = document.createElement("div");
      lb.textContent = g === "_root" ? "(root)" : g === "_unresolved" ? "(unresolved)" : g;
      lb.style.color = "var(--fg)"; lb.style.fontSize = "11px";
      row.appendChild(sw); row.appendChild(lb);
      legend.appendChild(row);
      groupRows.set(g, row);
      row.setAttribute("role", "button");
      row.setAttribute("tabindex", "0");
      row.addEventListener("mouseenter", () => { hoverGroup = g; renderGroup(); });
      row.addEventListener("mouseleave", () => { if (hoverGroup === g) { hoverGroup = null; renderGroup(); } });
      const toggle = () => {
        stuckGroup = (stuckGroup === g) ? null : g;
        renderGroup();
      };
      row.addEventListener("click", toggle);
      row.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); }
      });
    }

    const hud = mount.querySelector("#hud");
    const catsToggle = mount.querySelector("#hud-categories");
    // Desktop opens the legend by default; mobile keeps it collapsed.
    if (!COARSE) hud.classList.add("expanded");
    if (catsToggle) {
      const t = () => hud.classList.toggle("expanded");
      catsToggle.addEventListener("click", t);
      catsToggle.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); t(); }
      });
    }

    for (const n of data.nodes) {
      n.r = 2.2 + Math.sqrt(n.deg || 0) * 1.6;
      n.hot = 0;
      n.match = 0;
    }
    for (const l of data.links) l.hot = 0;
    let focusFactor = 0;

    const LAYOUT_CACHE_KEY = (opts.layoutCacheKey || "vault-graph-layout-v1")
      + `-${data.nodes.length}-${data.links.length}`;
    let cachedLayout = null;
    try { cachedLayout = JSON.parse(localStorage.getItem(LAYOUT_CACHE_KEY) || "null"); } catch {}
    if (cachedLayout) {
      for (const n of data.nodes) {
        const p = cachedLayout[n.id];
        if (p) { n.x = p[0]; n.y = p[1]; }
      }
    }

    const sim = d3.forceSimulation(data.nodes)
      .force("link", d3.forceLink(data.links).id(d => d.id).distance(36).strength(0.45))
      .force("charge", d3.forceManyBody().strength(-46).distanceMax(COARSE ? 200 : 420))
      .force("center", d3.forceCenter(0, 0).strength(0.04))
      .force("collide", d3.forceCollide().radius(d => d.r + 1.5).strength(0.9))
      .force("x", d3.forceX(0).strength(0.02))
      .force("y", d3.forceY(0).strength(0.02))
      .alpha(cachedLayout ? 0 : (COARSE ? 0.5 : 1))
      .alphaDecay(COARSE ? 0.04 : 0.018)
      .velocityDecay(COARSE ? 0.4 : 0.32);

    function saveLayout() {
      try {
        const out = {};
        for (const n of data.nodes) out[n.id] = [Math.round(n.x * 10) / 10, Math.round(n.y * 10) / 10];
        localStorage.setItem(LAYOUT_CACHE_KEY, JSON.stringify(out));
      } catch {}
    }
    sim.on("end", saveLayout);

    let transform = d3.zoomIdentity.translate(W/2, H/2).scale(1);
    let dirty = true;
    const markDirty = () => { dirty = true; };
    const zoomBehaviour = d3.zoom()
      .scaleExtent([0.1, 8])
      .on("zoom", (ev) => { transform = ev.transform; markDirty(); });
    d3.select(canvas).call(zoomBehaviour);
    d3.select(canvas).call(zoomBehaviour.transform, transform);
    sim.on("tick", markDirty);
    window.addEventListener("resize", markDirty);

    let hover = null;
    let dragNode = null;
    let highlight = new Set();
    let highlightLinks = new Set();
    let searchTerm = "";

    const nodeById = new Map(data.nodes.map(n => [n.id, n]));
    const neighbors = new Map();
    for (const n of data.nodes) neighbors.set(n.id, new Set());
    for (const l of data.links) {
      const s = typeof l.source === "object" ? l.source.id : l.source;
      const t = typeof l.target === "object" ? l.target.id : l.target;
      neighbors.get(s).add(t);
      neighbors.get(t).add(s);
    }

    function setHover(n) {
      hover = n;
      if (n) {
        highlight = new Set();
        highlightLinks = new Set();
        highlight.add(n.id);
        for (const nb of neighbors.get(n.id)) highlight.add(nb);
        for (const l of data.links) {
          if (l.source.id === n.id || l.target.id === n.id) highlightLinks.add(l);
        }
        markDirty();
      } else {
        // Mouse left a node — fall back to whatever group is pinned/hovered.
        renderGroup();
      }
    }

    function pick(mx, my) {
      const x = (mx - transform.x) / transform.k;
      const y = (my - transform.y) / transform.k;
      const HIT_PX = COARSE ? 22 : 16;
      const slop = HIT_PX / transform.k;
      // Hit area is max(n.r, slop): big nodes use their actual circle (no
      // bonus padding around the edge), small dots get a minimum slop-sized
      // pickable region. Scan all nodes because sim.find only returns the
      // nearest centre and loses to small neighbours around a big node.
      let best = null;
      let bestScore = Infinity;
      for (const n of data.nodes) {
        const dx = n.x - x, dy = n.y - y;
        const d2 = dx*dx + dy*dy;
        const reach = n.r > slop ? n.r : slop;
        if (d2 > reach * reach) continue;
        const score = Math.sqrt(d2) - n.r;
        if (score < bestScore) {
          bestScore = score;
          best = n;
        }
      }
      return best;
    }

    canvas.addEventListener("mousemove", (e) => {
      const r = canvas.getBoundingClientRect();
      const mx = e.clientX - r.left, my = e.clientY - r.top;
      if (midPan) {
        const dx = e.clientX - midPan.x;
        const dy = e.clientY - midPan.y;
        const t = d3.zoomIdentity.translate(midPan.tx + dx, midPan.ty + dy).scale(transform.k);
        d3.select(canvas).call(zoomBehaviour.transform, t);
        return;
      }
      if (dragNode) {
        const x = (mx - transform.x) / transform.k;
        const y = (my - transform.y) / transform.k;
        dragNode.fx = x; dragNode.fy = y;
        sim.alphaTarget(0.35).restart();
        markDirty();
        return;
      }
      const n = pick(mx, my);
      if (n !== hover) {
        setHover(n);
        canvas.style.cursor = n ? "pointer" : "grab";
      }
      if (n) {
        tooltip.textContent = n.label;
        tooltip.style.left = (e.clientX + 12) + "px";
        tooltip.style.top = (e.clientY + 12) + "px";
        tooltip.style.opacity = 1;
      } else {
        tooltip.style.opacity = 0;
      }
    });

    let pressInfo = null;
    let midPan = null;
    canvas.addEventListener("mousedown", (e) => {
      if (e.button === 1) {
        e.preventDefault();
        e.stopImmediatePropagation();
        midPan = { x: e.clientX, y: e.clientY, tx: transform.x, ty: transform.y };
        canvas.classList.add("dragging");
        return;
      }
      if (e.button !== 0) return;
      const r = canvas.getBoundingClientRect();
      const n = pick(e.clientX - r.left, e.clientY - r.top);
      pressInfo = { node: n, x: e.clientX, y: e.clientY, t: performance.now() };
      if (n) {
        e.stopImmediatePropagation();
        dragNode = n;
        dragNode.fx = n.x; dragNode.fy = n.y;
        canvas.classList.add("dragging");
        sim.alphaTarget(0.35).restart();
      }
    }, true);

    canvas.addEventListener("auxclick", (e) => { if (e.button === 1) e.preventDefault(); });
    canvas.addEventListener("contextmenu", (e) => { if (midPan) e.preventDefault(); });
    // Drop node-hover state when the cursor leaves the canvas — otherwise
    // hovering over the legend reads a stale `hover` and renderGroup bails
    // before it can show the category highlight.
    canvas.addEventListener("mouseleave", () => { tooltip.style.opacity = 0; if (hover) setHover(null); });

    window.addEventListener("mouseup", (e) => {
      if (e.button === 1 && midPan) {
        midPan = null;
        canvas.classList.remove("dragging");
        return;
      }
      const wasClick = pressInfo
        && Math.hypot(e.clientX - pressInfo.x, e.clientY - pressInfo.y) < 4
        && (performance.now() - pressInfo.t) < 320;
      const clickedNode = wasClick && pressInfo.node ? pressInfo.node : null;
      const voidClick = wasClick && !pressInfo.node && e.target === canvas;
      if (dragNode) {
        dragNode.fx = null; dragNode.fy = null;
        dragNode = null;
        canvas.classList.remove("dragging");
        sim.alphaTarget(0);
      }
      pressInfo = null;
      if (clickedNode) openNote(clickedNode);
      else if (voidClick) {
        if (!unstickGroup() && reader.classList.contains("open")) closeReader();
      }
    });

    const search = mount.querySelector("#search");
    search.addEventListener("input", () => {
      searchTerm = search.value.trim().toLowerCase();
      markDirty();
    });

    const EASE = 0.18;
    const DIM_FLOOR = 0.18;
    const EPS = 0.002;
    const HOT_BUCKETS = 6;

    const matchCache = { term: null, values: null };
    function refreshMatch() {
      if (matchCache.term === searchTerm) return;
      matchCache.term = searchTerm;
      if (!searchTerm) { matchCache.values = null; return; }
      const arr = new Uint8Array(data.nodes.length);
      for (let i = 0; i < data.nodes.length; i++) {
        arr[i] = data.nodes[i].label.toLowerCase().includes(searchTerm) ? 1 : 0;
      }
      matchCache.values = arr;
    }

    function tickFocus() {
      const focused = hover != null || searchTerm.length > 0
                   || hoverGroup != null || stuckGroup != null;
      const targetFocus = focused ? 1 : 0;
      let animating = Math.abs(targetFocus - focusFactor) > EPS;
      focusFactor += (targetFocus - focusFactor) * EASE;
      if (Math.abs(targetFocus - focusFactor) <= EPS) focusFactor = targetFocus;
      refreshMatch();
      const matches = matchCache.values;
      for (let i = 0; i < data.nodes.length; i++) {
        const n = data.nodes[i];
        const tH = highlight.has(n.id) ? 1 : 0;
        const dH = tH - n.hot;
        if (Math.abs(dH) > EPS) { n.hot += dH * EASE; animating = true; }
        else if (n.hot !== tH) n.hot = tH;
        const tM = matches ? matches[i] : 0;
        const dM = tM - n.match;
        if (Math.abs(dM) > EPS) { n.match += dM * EASE; animating = true; }
        else if (n.match !== tM) n.match = tM;
      }
      for (const l of data.links) {
        const t = highlightLinks.has(l) ? 1 : 0;
        const d = t - l.hot;
        if (Math.abs(d) > EPS) { l.hot += d * EASE; animating = true; }
        else if (l.hot !== t) l.hot = t;
      }
      return animating;
    }

    const hotPaths = new Array(HOT_BUCKETS);
    const FRAME_MIN_MS = COARSE ? 32 : 0;
    let lastDraw = 0;

    function draw(ts) {
      requestAnimationFrame(draw);
      if (ts && ts - lastDraw < FRAME_MIN_MS) return;
      const animating = tickFocus();
      const simRunning = sim.alpha() > sim.alphaMin();
      if (!dirty && !animating && !simRunning && !dragNode) return;
      lastDraw = ts || 0;
      dirty = false;

      ctx.clearRect(0, 0, W, H);
      ctx.save();
      ctx.translate(transform.x, transform.y);
      ctx.scale(transform.k, transform.k);

      const invK = 1 / transform.k;
      const vx0 = -transform.x * invK;
      const vy0 = -transform.y * invK;
      const vx1 = vx0 + W * invK;
      const vy1 = vy0 + H * invK;

      const drawColdLinks = !(COARSE && transform.k < 0.65);
      if (drawColdLinks) {
        const densityBoost = Math.min(1, 600 / Math.max(60, data.links.length));
        const coldAlpha = (0.18 + 0.45 * densityBoost) * (1 - focusFactor * 0.7);
        const stride = COARSE && transform.k < 1 ? 2 : 1;
        ctx.lineWidth = (0.6 + 0.5 * densityBoost) * invK;
        ctx.strokeStyle = `rgba(124,176,140,${coldAlpha})`;
        ctx.beginPath();
        for (let i = 0; i < data.links.length; i += stride) {
          const l = data.links[i];
          const sx = l.source.x, sy = l.source.y, tx = l.target.x, ty = l.target.y;
          if ((sx < vx0 && tx < vx0) || (sx > vx1 && tx > vx1) ||
              (sy < vy0 && ty < vy0) || (sy > vy1 && ty > vy1)) continue;
          ctx.moveTo(sx, sy);
          ctx.lineTo(tx, ty);
        }
        ctx.stroke();
      }

      for (let b = 0; b < HOT_BUCKETS; b++) hotPaths[b] = null;
      let anyHot = false;
      for (const l of data.links) {
        if (l.hot < 0.02) continue;
        const sx = l.source.x, sy = l.source.y, tx = l.target.x, ty = l.target.y;
        if ((sx < vx0 && tx < vx0) || (sx > vx1 && tx > vx1) ||
            (sy < vy0 && ty < vy0) || (sy > vy1 && ty > vy1)) continue;
        const b = Math.min(HOT_BUCKETS - 1, Math.floor(l.hot * HOT_BUCKETS));
        let p = hotPaths[b];
        if (!p) { p = hotPaths[b] = new Path2D(); }
        p.moveTo(sx, sy);
        p.lineTo(tx, ty);
        anyHot = true;
      }
      if (anyHot) {
        ctx.lineWidth = 1.2 * invK;
        for (let b = 0; b < HOT_BUCKETS; b++) {
          const p = hotPaths[b];
          if (!p) continue;
          const a = 0.85 * ((b + 0.5) / HOT_BUCKETS);
          ctx.strokeStyle = `rgba(0,255,102,${a})`;
          ctx.stroke(p);
        }
      }

      const nodePad = 4;
      for (const n of data.nodes) {
        if (n.x < vx0 - nodePad || n.x > vx1 + nodePad ||
            n.y < vy0 - nodePad || n.y > vy1 + nodePad) continue;
        const lit = n.hot > n.match ? n.hot : n.match;
        const alpha = 1 - focusFactor * (1 - lit) * (1 - DIM_FLOOR);
        ctx.globalAlpha = alpha;
        ctx.beginPath();
        ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2);
        ctx.fillStyle = groupColor[n.group] || "#888";
        ctx.fill();
        if (lit > 0.02) {
          ctx.globalAlpha = lit;
          ctx.lineWidth = 1.4 * invK;
          ctx.strokeStyle = "rgba(255,255,255,0.9)";
          ctx.stroke();
        }
      }
      ctx.globalAlpha = 1;

      const showLabels = transform.k > (COARSE ? 2.6 : 1.6);
      if (showLabels || focusFactor > 0.01) {
        ctx.font = `${11 * invK}px ui-sans-serif, system-ui, sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "top";
        const lpad = 60 * invK;
        for (const n of data.nodes) {
          if (n.x < vx0 - lpad || n.x > vx1 + lpad ||
              n.y < vy0 - lpad || n.y > vy1 + lpad) continue;
          const lit = n.hot > n.match ? n.hot : n.match;
          const labelAlpha = showLabels
            ? (1 - focusFactor * (1 - lit) * 0.9)
            : lit;
          if (labelAlpha < 0.04) continue;
          const y = n.y + n.r + 2 * invK;
          ctx.globalAlpha = labelAlpha * 0.55;
          ctx.fillStyle = "#000";
          ctx.fillText(n.label, n.x + 0.6 * invK, y + 0.6 * invK);
          ctx.globalAlpha = labelAlpha;
          ctx.fillStyle = lit > 0.5 ? "#fff" : "rgba(230,230,230,0.92)";
          ctx.fillText(n.label, n.x, y);
        }
        ctx.globalAlpha = 1;
      }

      ctx.restore();
    }
    requestAnimationFrame(draw);

    canvas.addEventListener("dblclick", (e) => {
      const r = canvas.getBoundingClientRect();
      const n = pick(e.clientX - r.left, e.clientY - r.top);
      if (n) {
        panTo(n, Math.max(transform.k, 2.2));
      } else {
        d3.select(canvas).transition().duration(420)
          .call(zoomBehaviour.transform, d3.zoomIdentity.translate(W/2, H/2).scale(1));
      }
    });

    const reader = mount.querySelector("#reader");
    const readerTitle = mount.querySelector("#reader-title");
    const readerCrumb = mount.querySelector("#reader-crumb");
    const readerBody = mount.querySelector("#reader-body");
    const readerActions = mount.querySelector("#reader-actions");
    const readerExtras = mount.querySelector("#reader-extras");
    const readerCloseBtn = mount.querySelector("#reader-close");
    readerCloseBtn.addEventListener("click", closeReader);
    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && reader.classList.contains("open")) closeReader();
    });

    let readerNode = null;
    let currentNoteId = null;
    let activePanel = null;

    readerTitle.addEventListener("mouseenter", () => { if (readerNode) setHover(readerNode); });
    readerTitle.addEventListener("mouseleave", () => { if (hover === readerNode) setHover(null); });
    readerTitle.addEventListener("click", () => {
      if (readerNode) panTo(readerNode, Math.max(transform.k, 1.8));
    });

    function closeReader() {
      reader.classList.remove("open");
      reader.setAttribute("aria-hidden", "true");
      readerNode = null;
      currentNoteId = null;
      readerExtras.innerHTML = "";
      // Strip any plugin-added action buttons (keep the close button).
      for (const btn of Array.from(readerActions.querySelectorAll("button[data-vg-plugin]"))) {
        btn.remove();
      }
      if (activePanel) {
        activePanel = null;
        if (typeof opts.onPanelClose === "function") opts.onPanelClose();
      }
    }

    function panTo(n, k) {
      // Derive the visible region from the known CSS values instead of the
      // mid-transition getBoundingClientRect (which is off-screen right after
      // .open is added). Desktop: right panel = min(560px, 46vw). Mobile:
      // bottom sheet = 55vh tall, full-width.
      let cx = W / 2;
      let cy = H / 2;
      if (reader.classList.contains("open")) {
        if (W <= 720) {
          const sheetH = H * 0.55;
          cy = (H - sheetH) / 2;
        } else {
          const sheetW = Math.min(560, W * 0.46);
          cx = (W - sheetW) / 2;
        }
      }
      const t = d3.zoomIdentity.translate(cx - n.x * k, cy - n.y * k).scale(k);
      d3.select(canvas).transition().duration(380)
        .call(zoomBehaviour.transform, t);
    }

    function rewriteWikilinks(md) {
      return md.replace(WIKILINK_MD, (_m, target, _a, alias) => {
        const id = target.trim().toLowerCase();
        const display = (alias || target).trim();
        const node = nodeById.get(id);
        const cls = node && node.path ? "wikilink" : "wikilink unresolved";
        const titleAttr = node ? "" : ' title="unresolved"';
        const safe = escapeHTML(display);
        return `<a class="${cls}" data-id="${id.replace(/"/g, "&quot;")}"${titleAttr}>${safe}</a>`;
      });
    }
    if (window.marked) marked.setOptions({ gfm: true, breaks: false });
    function renderMarkdown(raw) {
      const stripped = raw.replace(FRONTMATTER, "");
      return marked.parse(rewriteWikilinks(stripped));
    }

    readerBody.addEventListener("click", (e) => {
      const a = e.target.closest("a.wikilink");
      if (!a) return;
      e.preventDefault();
      if (a.classList.contains("unresolved")) return;
      const node = nodeById.get(a.dataset.id);
      if (node) openNote(node);
    });

    const noteCache = new Map();

    async function openNote(node) {
      if (!node || !node.path) {
        reader.classList.add("open");
        reader.setAttribute("aria-hidden", "false");
        readerTitle.textContent = node ? node.label : "";
        readerCrumb.textContent = "unresolved";
        readerBody.innerHTML = `<div class="empty">No note file for <b>${node ? escapeHTML(node.label) : ""}</b>.</div>`;
        readerExtras.innerHTML = "";
        return;
      }
      if (currentNoteId === node.id && reader.classList.contains("open")) return;
      currentNoteId = node.id;
      readerNode = node;
      reader.classList.add("open");
      reader.setAttribute("aria-hidden", "false");
      readerTitle.textContent = node.label;
      readerCrumb.textContent = node.group === "_root" ? "" : node.group;
      setHover(node);
      panTo(node, transform.k < 1.4 ? 1.6 : transform.k);

      // Reset plugin-added buttons + extras for each open.
      for (const btn of Array.from(readerActions.querySelectorAll("button[data-vg-plugin]"))) {
        btn.remove();
      }
      readerExtras.innerHTML = "";

      let raw = noteCache.get(node.id);
      if (raw == null) {
        readerBody.innerHTML = `<div class="empty">Loading…</div>`;
        try {
          raw = await opts.fetchNote(node.path);
          noteCache.set(node.id, raw);
        } catch (err) {
          readerBody.innerHTML = `<div class="empty err">Failed to load: ${escapeHTML(err.message || String(err))}</div>`;
          return;
        }
      }
      if (currentNoteId !== node.id) return;
      readerBody.innerHTML = renderMarkdown(raw);
      readerBody.scrollTop = 0;

      const panel = {
        node,
        raw,
        get currentRaw() { return noteCache.get(node.id); },
        bodyEl: readerBody,
        actionsEl: readerActions,
        extrasEl: readerExtras,
        addAction(label, onClick, opts2 = {}) {
          const btn = document.createElement("button");
          btn.type = "button";
          btn.textContent = label;
          if (opts2.primary) btn.classList.add("primary");
          if (opts2.title) btn.title = opts2.title;
          btn.dataset.vgPlugin = "1";
          btn.addEventListener("click", onClick);
          // Insert before the close button.
          readerActions.insertBefore(btn, readerCloseBtn);
          return btn;
        },
        setBodyHTML(html) { readerBody.innerHTML = html; readerBody.scrollTop = 0; },
        setBodyMarkdown(md) {
          noteCache.set(node.id, md);
          readerBody.innerHTML = renderMarkdown(md);
          readerBody.scrollTop = 0;
        },
        restoreBody() {
          readerBody.innerHTML = renderMarkdown(noteCache.get(node.id) || raw);
        },
        setExtras(html) {
          if (typeof html === "string") readerExtras.innerHTML = html;
          else { readerExtras.innerHTML = ""; readerExtras.appendChild(html); }
        },
        close: closeReader,
        panTo: (k) => panTo(node, k ?? Math.max(transform.k, 1.8)),
        renderMarkdown,
      };
      activePanel = panel;
      if (typeof opts.onPanelOpen === "function") {
        try { opts.onPanelOpen(panel); } catch (err) { console.error("onPanelOpen threw:", err); }
      }
    }

    return {
      data,
      openNote: (idOrNode) => {
        const n = typeof idOrNode === "string" ? nodeById.get(idOrNode) : idOrNode;
        if (n) openNote(n);
      },
      reload: async () => {
        const fresh = await opts.fetchGraph();
        // For now reload simply replaces in-place; full re-layout requires a reload of the page.
        // Callers usually do location.reload() after structural changes.
        return fresh;
      },
      getActivePanel: () => activePanel,
      getCurrentUserCount: () => data.nodes.length,
      destroy: () => {
        mount.querySelectorAll("#c, #hud, #site-footer, #tooltip, #reader").forEach(el => el.remove());
      },
    };
  }

  root.VaultGraph = { create };
})(window);
console.info('vault-graph build 9862541c loaded');
