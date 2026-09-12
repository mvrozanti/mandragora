---
name: elicit
description: Use when a decision will be made by looking — UI/UX, layout, visual identity, information architecture, a redesign or migration of an existing surface, "which of these should it be", "make it look better". Ships several working directions as one published, fully interactive HTML artifact wired to real data, then builds exactly the one chosen. Use instead of AskUserQuestion whenever the options differ in how they look or behave rather than in what outcome they produce. Triggered explicitly via /elicit.
---

# elicit — Show the Options, Don't Describe Them

## Overview

Prose about a design is not a design. A bulleted list of approaches is not a
design. A single built page is not a choice — it is a fait accompli the user
can only react to.

For any decision the user will make **by looking**, the deliverable is a
published artifact containing several working directions they click through
and pick from.

**The law:** if two options differ in how they *look* or *feel*, they must be
**shown**. If they differ only in what becomes *true*, they may be **asked**.

| Decision | Skill |
|---|---|
| "Should this break loudly or stay frozen?" | `confused` — text, objectives |
| "Which layout / which identity / which IA?" | **`elicit`** — artifact, directions |
| "Should it land today or park until reviewed?" | `confused` |
| "How should dream and the graph relate?" | **`elicit`** |
| "Who else needs to reuse this?" | `confused` |
| "Make it look better" | **`elicit`** |

When a task has both kinds, elicit first — the visual choice usually deletes
half the text questions.

## Lineage

This is the house pattern, not an invention. It produced `chess.mvr.ac`'s
`ux-design-directions.html`, the `hub.mvr.ac` rebuild, the `--mv-*` design
system, and the `watch.mvr.ac` migration. Match it.

## When to Use

- Any new UI, or any reshaping of an existing one.
- Visual identity, palette, typography, layout, motion.
- Information architecture — what the app is *organized by*.
- A migration onto an existing design system, where "how faithful" is the real
  question.
- The user says "make it better", "modernize", "clean up the UI", "I don't like
  how it looks", or names two things that should become one.

**Do NOT use when:**

- The user already specified the design. Build it.
- There is one obvious answer and the change is reversible. Build it, say what
  you chose.
- The decision is about behaviour, cost, scope, or risk with no visual
  component — that is `confused`.
- It is a bug fix wearing a UI costume.

## Workflow

```
1. Inventory   Enumerate EVERY capability of the current surface. Gate, below.
2. Axis        Name the one structural conflict the directions will resolve.
3. Cut         Design N directions that disagree on mechanism. Default N=5;
               N=10 when the user asks for breadth or the surface is large.
4. Kernel      Build one shared core: real data, real engines, real state.
5. Compose     Each direction is a layout over the kernel. Mount one at a time.
6. Argue       Every direction gets a ledger and a verdict. State your pick.
7. Publish     One artifact. Hand over the link and the recommendation.
8. Build       Implement the chosen direction EXACTLY. No substitutions.
```

## 1. The Inventory Gate (non-negotiable for existing surfaces)

Before proposing any redesign, enumerate what exists today: every control,
every gesture, every keyboard binding, every modal, every background poll,
every conditional surface (logged-out, read-only, empty, error).

Mechanical, not from memory:

```bash
grep -oE '<(button|input|select|textarea|a|details)\b[^>]*' index.html
grep -oE '(e|ev)\.key\s*===?\s*"[^"]+"' app.js | sort -u
grep -nE 'addEventListener\("(pointer|wheel|contextmenu|touch)' *.js
grep -oE 'setInterval\([^,]{0,40},\s*[0-9]+' app.js | sort -u
```

Then:

- **Ship the inventory with the artifact.** The user must be able to check your
  work against it.
- **Every direction accounts for every item.** Moved, merged, or renamed is
  fine — and say which. Absent is not.
- **Grouping is a proposal; removal is a bug.** Folding two pages into one
  section with two tabs is a direction. Silently dropping one is a regression
  you will be caught on, and rightly.
- If a direction genuinely requires dropping something, that goes in its
  `gives up` row in words, as a cost the user is choosing.

> This gate exists because it was violated: a Workbench mockup silently dropped
> an 8-item queue and merged two renderers into one unnamed section. The
> directions were fine. The omissions poisoned them.

## 2. Name the Axis

A deck of directions is only useful if they disagree about something nameable.
Write the conflict in one sentence before designing anything.

> *"What is this app organized by — the lineage of what you made, the output you
> are looking at, the time it happened, or the machine constraint underneath?"*

If you cannot write that sentence, you do not have directions, you have themes.

## 3. Cutting the Directions

**They must disagree on mechanism** — information architecture and interaction
model — **not on palette.** Five colour variations of one layout is one
direction shown five times.

Useful axes to spread across:

| Axis | Example poles |
|---|---|
| Primary surface | canvas · stage · feed · single focus · command line |
| Organizing principle | lineage · output · time · attention · constraint |
| Where the new thing lives | a node · a mode · a section · a verb · a sheet |
| Chrome cost | zero chrome ↔ full IDE |
| Risk | closest to today ↔ complete reframe |

Rules:

- Include one **conservative** direction (closest to today) and one **most
  distinctive**. Without the first the deck feels reckless; without the second
  it feels timid.
- No two directions may share an organizing principle.
- Each gets a short name a person would actually say — *Dream is a node*, *The
  Stage*, *Command palette* — never *Option C*.
- Round one is a **probe, not a verdict**. Expect a round two that merges two
  or three. Design for that: keep the kernel reusable.

## 4. Real Data, Never Lorem

A mockup wired to invented numbers cannot be judged. Pull from the live system:

- Real record counts, real IDs, real tree shape, real timings.
- Real option lists — the actual model names, the actual slider ranges and
  defaults, the actual endpoint names on the controls.
- The real palette from wherever the real one comes from.
- Real empty states. If there are 0 LoRAs installed, show 0.

Read structure straight out of the source of truth:

```bash
sqlite3 "$DB" "SELECT id, parent_id, mode, width, height FROM generations ORDER BY id;"
```

**Substitution rules.** Some real content must not be reproduced:

| Content | Do |
|---|---|
| Encrypted or secret values | Substitute, and **say so in the artifact** |
| Private user imagery | Generate procedural stand-ins, deterministic per ID |
| Anything under `secrets/` | Never read it. Never. |
| NSFW-flagged material | Never reproduce; keep the *flag* and its gating |

Label every substitution in the footer. An unlabelled stand-in is a lie the
user will act on.

## 5. The Interactivity Bar

"Fully interactive and functional" is the requirement, not an aspiration.

Each direction must actually:

- Respond to every control it shows. A slider that does not move is a bug.
- Run its real engine — a force graph simulates, a stream streams, a filter
  filters. Approximate the *mechanic*, not a video of it.
- Enforce the real constraints. If the backend serialises on a lock, starting
  one thing must visibly block the other, with the real holder name.
- Honour the real keyboard map.
- Work at both viewports. Ship a phone/desktop toggle if the surface has a
  mobile story.
- Open **at rest in a working state** — populated, settled, nothing waiting on
  a scroll or an observer.

A direction you cannot click is a screenshot with extra steps.

See `reference/build-kernel.md` for the one-file architecture that makes N
interactive directions affordable.

## 6. The Ledger and the Verdict

Every direction carries the same four-row ledger plus a verdict. Same rows in
the same order, so they can be compared by scanning one column.

| Row | Contents |
|---|---|
| `touches` | Which files and which layer of each |
| `adds` | Rough new line count and any new primitive |
| `removes` | What stops existing — usually the good news |
| `gives up` | The honest cost, in the user's terms |

The verdict is one short paragraph that **takes a position**: recommend, mixed,
or against. Argue against your own weak directions — a deck where every option
sounds good is a deck with no information in it. Mark exactly one as the pick
and say why, and name the runner-up and what would make it win instead.

Never include a direction you would refuse to build. If it is in the deck, it
is on offer.

## 7. Publishing

One artifact, all directions, via the Artifact tool.

- Deck chrome must be **visually distinct from the specimens** — different
  typeface, different neutral — so the frame is never mistaken for the design.
- Put each specimen in a device frame with the real hostname. It sells "this is
  your site", and it makes the viewport toggle legible.
- Mount **only the active direction**; tear down the previous one's timers,
  animation frames, and observers.
- Provide the switchers the decision needs: viewport, theme or palette, and any
  state that changes the answer (empty vs populated, logged-out vs in).
- Open on your recommended direction.
- Title is a name, not a caption. Description says what it is for.

Hand over: the link, the axis, the pick with its one-line reason, and the
strongest objection to your own pick.

## 8. After the Pick

- Build the chosen direction **exactly**. The deck was a contract.
- Re-run the inventory gate against the thing you are about to build. Every
  item lands somewhere, or is listed as a stated cost the user already chose.
- If the pick has a genuinely open sub-decision, it is usually still visual —
  run a **round two** deck scoped to that one question rather than reverting to
  text.
- If something in the chosen direction turns out to be impossible, stop and say
  so before building. Never silently substitute — that is how a chosen design
  becomes a design the user never approved.
- Save the decision and its *why* to the vault; the deck answers "what", the
  note answers "why this one".

## Critical Rules

1. **Show, never describe.** If it is visual, it is an artifact. A text list of
   design options is the failure this skill exists to prevent.
2. **Inventory first.** Never propose a redesign of a surface you have not
   fully enumerated. Ship the enumeration.
3. **Never remove functionality.** Grouping is a proposal; deletion is a
   regression. Anything given up is named as a cost, in words.
4. **Real data only.** Label every substitution. Never touch `secrets/`.
5. **Directions disagree on mechanism.** Palette variants are not directions.
6. **Everything works.** Every control responds; every real constraint is
   enforced.
7. **Take a position.** One pick, one reason, one honest objection to it.
8. **Build exactly what was chosen.** No silent substitutions, ever.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Asking a visual question as a text multiple-choice | Build the deck. This is the whole point. |
| Describing the options in chat and asking which | Same. Prose is not a proposal. |
| One built page, "how's this?" | That is not a choice. Ship several. |
| Directions that differ only in colour | Re-cut along mechanism. Name the axis. |
| Silently dropping an existing feature | Inventory gate. Grouping is fine; deletion is not. |
| Lorem, fake counts, invented model names | Read the real system. |
| Static mockups | Wire the controls and run the real engine. |
| Every option sounds great | You omitted the costs. Fill the `gives up` row. |
| No recommendation | Pick one, argue it, name the runner-up. |
| Treating round one as final | It is a probe. Expect a merge round. |
| Building "basically" the chosen one | Build exactly it, or say why you cannot. |
