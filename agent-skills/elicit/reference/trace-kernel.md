# Trace Kernel — N traceable designs in one artifact

Load this when writing the deck. It shares its frame with `elicit-ui`'s build
kernel; read these sections of `~/.claude/skills/elicit-ui/reference/build-kernel.md`
first and follow them unchanged: **Registry and mount discipline**, **Artifact
constraints**, **Verify**. This file covers only what differs: the specimen is a
diagram the bench runs on, not a page.

## Shape

Keep the deck's data in a module and generate the HTML with a build script in
the scratchpad. The build script runs the static checks (below) and refuses to
emit a deck that fails them.

```
deck/
  data.mjs     grid · scenarios · criteria · inventory · floor · directions
  build.mjs    checks, then renders one HTML file
  deck.html    the artifact
```

One HTML file, in this order:

```
1  deck chrome CSS      rail, axis table, consequence strip, ledger, verdict
2  diagram CSS          node kinds, edge states, outcome tokens
3  kernel JS            grid renderer · tracer · matrix + weights · heatmap
4  direction data       one registry entry each, then deck wiring
```

## One grid for every direction

The same lanes and the same fixed positions for everything every direction
shares, so switching directions shows what moved:

```js
const GRID={cols:7,lanes:["entry","core","state","outside"],cell:[150,92]};
const FIXED={
  legacy:{c:0,l:3,kind:"ext",label:"legacy backend"},
  partnerA:{c:4,l:3,kind:"ext",label:"partner A"},
  partnerB:{c:5,l:3,kind:"ext",label:"partner B"}};
```

Node kinds: `svc` (rectangle), `store` (cylinder), `queue` (double-bar),
`ext` (dashed — not ours), `human` (a step someone does by hand). `truth`
lists the entities whose source of truth this node is; the renderer draws ★.

## A direction

```js
reg({ key:"core", name:"One core, many replicas",
  axis:"In one process; transitions coordinated in-process",
  prose:"…three sentences at most…",
  nodes:[
    {id:"api",c:1,l:0,kind:"svc",label:"api"},
    {id:"core",c:2,l:1,kind:"svc",label:"core ×N"},
    {id:"db",c:2,l:2,kind:"store",label:"postgres",truth:["record"]},
    {id:"relay",c:3,l:2,kind:"svc",label:"outbox relay"},
    {id:"legacy",...FIXED.legacy}],
  edges:[["api","core","command"],["core","db","tx"],["db","relay","outbox"]],
  trace:{
    dup:[{at:"api",note:"callback arrives twice"},
         {at:"core",note:"inbox already has event_id",st:"ok"}]},
  outcome:{dup:["handled","inbox dedupes on event_id"]},
  change:{newPartner:{nodes:["gw"],count:"1 deployable · 1 adapter"}},
  scores:{scale:[4,"stateless replicas; the database is the ceiling (measured: see Numbers)"]},
  numbers:[["p99 command latency","40–90 ms","assumes one db round trip per command"]],
  types:`type Record = { id: RecordId; state: State; version: number }`,
  inventory:{"webhook receiver":"moved to ingress"},
  ledger:[["Touches","…"],["Adds","…"],["Removes","…"],["Operates","…"],["Gives up","…"],["Undo","…"]],
  verdict:{tone:"pick",txt:"…"} });
```

`Today` is registered the same way with `today:true`: it renders, it traces,
it appears pinned at the top of the matrix, and it is never ranked.

## Shared registries

Scenarios, criteria, changes, and inventory are declared once and every
direction must answer all of them:

```js
const SCENARIOS=[
  {key:"happy",name:"Happy path"},
  {key:"dup",name:"Callback delivered twice"},
  {key:"down",name:"Partner A down for four hours"},
  {key:"replay",name:"Replay yesterday's dead letters"},
  {key:"newPartner",name:"Add a fourth partner"},
  {key:"x10",name:"Ten times the volume"},
  {key:"3am",name:"A new engineer debugging at 3 a.m."}];
const CRITERIA=[{key:"scale",name:"Horizontal scale",w:3},{key:"consistency",name:"Data consistency",w:3},{key:"speed",name:"Delivery speed",w:3}];
const OUTCOME={handled:["✓","handled"],degraded:["~","degraded"],wrong:["✗","wrong state"],human:["✋","needs a human"]};
```

## Tracer

State is `{dir, scenario, step}` and lives outside any direction, so a mount
never resets it — switching direction keeps the scenario and clamps the step to
the new trace's length.

- Each step's `at` is a node id or an edge written `"a>b"`.
- The current step is lit; earlier steps stay as a dimmed trail; stores the
  trace has written to carry a *persisted* badge.
- The note panel shows `step i / n`, the note, and on the last step the outcome
  chip from `OUTCOME` — glyph plus word.
- `←` `→` step, `space` plays at ~900 ms per step, `1`–`9` pick a scenario.
- Playback is a `setTimeout` chain owned by the deck, cancelled on every mount
  and on every manual step.

## Matrix and weights

Rows: `Today` pinned, then directions sorted by weighted score. Columns: one
per criterion (score and its justification on hover or tap), then one per
scenario (outcome glyph). Clicking a scenario cell mounts that direction on that
scenario at its last step. Weight sliders (0–5) re-sort live; ties keep deck
order. Show the weighted total, so the ranking can be checked by hand.

## Change heatmap

A change picker over the `change` registry. The selected change tints every node
listed for it on the current direction's diagram and shows its count chip.
Switching direction keeps the selected change — the user is comparing blast
radius.

## Mermaid, for static diagrams only

The floor, the merge proposal for round two, and any picture the bench does not
run on may use Mermaid. Claude.ai artifacts render `<pre class="mermaid">`
natively — do not load the library. Keep every diagram in the DOM (switch tabs by
scrolling or highlighting, never `display:none`) so the renderer measures a real
width. Validate every block before publishing with the parser already on this
box: `mermaid@11.13.0` and `happy-dom` under
`~/Projects/claude-devtools/node_modules/.pnpm/`, `mermaid.parse()` per block.

What the parser does not catch: `direction` inside a subgraph is ignored when
the subgraph has edges to the outside; return flows drawn as arrows create
layout cycles (draw them as dotted links without arrowheads); quote any label
with punctuation.

## Theming

Colour tokens on `:root` with a dark-mode override, per `artifact-design`.
Outcome tokens (`--ok`, `--warn`, `--bad`, `--human`) are never the only signal:
every outcome also carries its glyph and word. External nodes are distinguished
by a dashed stroke, not by colour.

## Static checks (in build.mjs, before any rendering)

Fail the build, naming the direction and key, when:

- a direction lacks a `trace` or an `outcome` for any scenario;
- a step's `at` resolves to no node or edge of that direction;
- a direction lacks a score or a justification for any criterion;
- a direction lacks an `inventory` mapping for any inventory item;
- a direction lacks a `change` entry for any anticipated change;
- a ledger does not have exactly the six rows, in order;
- two directions give the same `axis` line;
- a `FIXED` node appears at a different cell in some direction;
- the number of `pick` verdicts is not exactly one.

Then the jsdom pass and the single screenshot from the shared build kernel.
Assert behaviour: step through one scenario on two directions with real key
events and check that the step and the scenario survive the switch.
