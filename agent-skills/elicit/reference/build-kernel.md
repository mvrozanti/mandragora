# Build Kernel — N interactive directions in one artifact

Load this when writing the deck. It is the architecture that makes ten
*working* directions cost about as much as two.

## Shape

One HTML file, five layers, in this order:

```
1  deck chrome CSS      the frame: rail, bezel, ledger, verdict
2  specimen CSS         the real design tokens, re-rooted (below)
3  per-direction CSS    layout only, one scoped block each
4  kernel JS            data · stand-ins · engines · shared state
5  direction JS         one registry entry each, then deck wiring
```

Directions are **compositions over the kernel**, never copies of it. If a
direction needs its own engine, the axis is wrong or the kernel is too thin.

## Frame vs specimen

The deck must never be mistaken for the design. Give the chrome a different
typeface and a different neutral than any specimen, and put each specimen in a
device frame carrying the real hostname.

**Re-root the design tokens.** Real systems define tokens on `:root`. In the
deck that would repaint the chrome too, so scope them to the specimen element
and keep the values verbatim:

```css
.spec{
  --mv-bg:#13140d; --mv-accent:#bbcf81; /* copied verbatim, not retyped */
  position:absolute; inset:0; overflow:hidden;
  background:var(--mv-bg); color:var(--mv-text);
  container-type:inline-size;   /* see Responsiveness */
}
```

Apply palettes with the **same mapping the real loader uses**, so what the user
judges is what will ship:

```js
const TOKENS = {surface:"--mv-bg", primary:"--mv-accent", /* …from theme.js */};
Object.keys(TOKENS).forEach(k=>{ if(t[k]) spec.style.setProperty(TOKENS[k],t[k]) });
```

State colours that the real system deliberately excludes from theming stay
excluded here. Reproducing the exclusion is part of the fidelity.

## Responsiveness

A specimen in a 390px bezel inside a wide page must lay out as if the *viewport*
were 390px. Media queries read the window and will lie to you. Use container
queries against the specimen root:

```css
.spec{ container-type:inline-size; }
@container (max-width:620px){ .d2{ grid-template-columns:1fr; } }
```

## Registry and mount discipline

```js
const DIRECTIONS=[]; const reg=d=>DIRECTIONS.push(d);

reg({ key:"modes", name:"Two modes of one canvas", tag:"renderer",
      mech:"Organized by renderer · one prompt, two outputs",
      prose:`<p>…</p>`,
      verdict:{tone:"", lbl:"The recommendation", txt:"…"},
      ledger:[["Touches","…"],["Adds","…"],["Removes","…"],["Gives up","…"]],
      build(root){ /* … */ return ()=>{ /* teardown */ }; } });
```

`build(root)` returns a teardown. **Mount exactly one direction at a time** and
always call the previous teardown — otherwise every visited direction keeps its
`requestAnimationFrame` loop, `setInterval`, and `ResizeObserver` running, and
the deck degrades as it is browsed.

```js
function mount(i){
  if(teardown){try{teardown()}catch(e){}}
  viewport.textContent="";
  specRoot=el("div","spec"); viewport.appendChild(specRoot);
  applyPalette(palette);               // before build, so engines read real tokens
  teardown=DIRECTIONS[i].build(specRoot);
}
```

Teardown must cancel every rAF and interval, disconnect observers, and reset
shared engines to idle — including releasing any simulated lock.

## Data layer

Real structure, read from the source of truth, as a literal array. Keep the real
IDs; gaps in the sequence are information.

```js
const NODES=[
  {id:2, p:null, m:"text",     w:512,  h:512,  s:25.7},
  {id:3, p:2,    m:"outpaint", w:512,  h:512,  s:24.0},
];
```

Carry the real option lists — model names, backbone labels, slider `min`/`max`/
`step`/default — copied from the markup, not approximated. Put real endpoint
paths in the controls' notes; they are free fidelity and they help the build.

## Procedural stand-ins

Deterministic per ID so a node looks the same everywhere, and cached:

```js
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;
  let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;
  return((t^t>>>14)>>>0)/4294967296}}
```

Make the *kind* legible in the mark — an outpaint shows its original frame, an
inpaint its patch, a morph its two-tone blend. That is what makes the graph
readable rather than decorative.

## Engines

Approximate the **mechanic**, not a recording of it.

- A feedback-zoom stream really is: draw the canvas onto itself scaled by
  `zoom_factor`, then paint structure over it. Vary the structure generator by
  model so the model picker visibly does something.
- A force graph really does run its constants. **Copy them from the source**,
  and copy the formula too — a term scaled differently than the original
  collapses the layout into a blob and you will blame the constants.

Two rules for anything simulated:

1. **Pre-settle.** Run the simulation to rest synchronously at construction,
   then fit the camera, then draw. The first painted frame must already be the
   good one — this is also the only way a single-frame screenshot shows truth.
2. **Survive zero size.** A canvas built inside a hidden or unlaid-out container
   reports `clientWidth === 0`. Re-measure on the next frame rather than baking
   a 1px backing store:

```js
resize(){const w=cv.clientWidth,h=cv.clientHeight;
  if(!w||!h){requestAnimationFrame(()=>this.resize());return} /* … */}
```

## Shared constraints

Model the real serialisation as one small store every direction reads, so
contention behaves identically across the deck:

```js
const gpu={holder:null,since:0,subs:new Set(),
  take(n){this.holder=n;this.since=performance.now();this.emit()},
  release(){this.holder=null;this.emit()},
  on(f){this.subs.add(f);f(this);return()=>this.subs.delete(f)}};
```

Then the blocked state is real everywhere: the primary action disables and names
the holder, instead of silently failing the way the current app does.

## Artifact constraints

- Scripts only from the allowed CDNs; fonts only from Google Fonts. Everything
  else inline. Most decks need no library at all.
- Write page content only — no `<!DOCTYPE>`, `<html>`, `<head>`, `<body>`.
- The rendered page must open at rest, populated, nothing waiting on scroll.

## Verify: jsdom for behaviour, one screenshot for paint

**Run it under jsdom first** — a thrown error leaves a blank bezel that looks
like a CSS bug. `new Function(src)` is **not** enough: it parses in function
scope, so a top-level `function top(){}` (or `name`, `status`, `length`, `self`,
`parent`, `origin`, `location`, `history`, `closed`, `frames`) compiles clean
there while being a whole-script `SyntaxError` in a real document.

```js
const {JSDOM,VirtualConsole}=require("jsdom");
const vc=new VirtualConsole(); vc.on("jsdomError",e=>{console.error("ERR",e.message)});
const html=require("fs").readFileSync("deck.html","utf8");
const dom=new JSDOM('<!doctype html><html><head></head><body>'+html+'</body></html>',
  {runScripts:"dangerously", virtualConsole:vc,
   beforeParse(w){ w.matchMedia=()=>({matches:false,addEventListener(){},removeEventListener(){}}) }});
```

Then assert behaviour, not presence: dispatch real `MouseEvent`s at the rail and
the controls, and re-count the DOM afterwards. Wrap each direction's script in an
IIFE so no top-level name can collide with a `window` property.

jsdom does not paint, so it cannot catch layout. Take exactly one screenshot for
that, then one pass of fixes:

```bash
{ printf '<!doctype html><html><head><meta charset="utf-8"></head><body>';
  cat deck.html; printf '</body></html>'; } > preview.html
firefox --headless --profile "$PWD/ffprof" --window-size 1500,900 \
        --screenshot "$PWD/shot.png" "file://$PWD/preview.html"
```

(`--screenshot` works on this box; it is *geckodriver* that crashes. No chromium.)

Do not build a test loop beyond that. The live artifact is the review surface.
