---
name: elicit
description: Use when a decision will be made by understanding how something works rather than by looking at it — architecture, service boundaries, data model or ontology ("what is X", "where does the truth live", "how should A and B relate"), API/protocol contracts, consistency and failure semantics, pipeline and workflow design, build-vs-buy, migration strategy. Ships several competing designs as one published, interactive artifact — diagram first, the same scenarios traced through every design, criteria the user weights to re-rank them live — then builds exactly the one chosen. The structural sibling of elicit-ui: hands visual decisions to it and outcome questions to confused. Triggered explicitly via /elicit.
---

# elicit — Trace the Options, Don't Argue Them

## Overview

A paragraph of pros and cons is not a design. A comparison table of buzzwords
is not a design. A single architecture diagram is not a choice — it is a fait
accompli the user can only react to.

For any decision about **how a system works**, the deliverable is a published
artifact in which several competing designs are drawn, and the same scenarios
are traced through every one of them, step by step.

**The law, completed:**

| The options differ in… | Verb | Skill |
|---|---|---|
| what becomes *true* | **ask** | `confused` |
| how it *looks* or *feels* | **show** | `elicit-ui` |
| how it *works* — where state lives, what moves, what breaks, what a change costs | **trace** | **`elicit`** |

| Decision | Skill |
|---|---|
| "Should this break loudly or stay frozen?" | `confused` |
| "Which layout should the dashboard have?" | `elicit-ui` |
| "Where does the truth about an order live, and who moves it along?" | **`elicit`** |
| "Is a generation a node, an event, or a file?" | **`elicit`** |
| "One service, nine services, or a workflow engine?" | **`elicit`** |
| "Build it or rent it?" | **`elicit`** |
| "How should dream and the graph relate?" | whichever face constrains the other — see below |

A decision with two faces: settle the face that constrains the other first.
For a backend that is usually structure, then surface; for a product, usually
surface, then structure. Each deck is still one decision.

## The Ownership Test

`confused` and AGENTS.md's decision discipline both say mechanism is the
agent's call. `elicit` is the exception, and it needs a reason. Elicit only if
at least one holds:

- **The user will defend it to other people** — a day job, a design review, a
  team that inherits it.
- **It is a one-way door** — identity, data model, source of truth, a public
  contract, anything whose reversal is a migration.
- **The candidates trade properties the user may weight differently** —
  consistency vs latency, control vs operating burden, speed now vs speed in a
  year — and the weighting is theirs.

Otherwise the mechanisms are equivalent for the user's purposes. Pick one,
build it, say which.

## Lineage

Generalised from an 8-direction service-architecture deck for a day-job
integration (2026-09-27), which ran `elicit-ui`'s method on a backend. The
round-one verdict on it was *too much talk for too little graph*. Every rule
below about diagrams-first and capped prose comes from that.

## When to Use

- Architecture: topology, service or module boundaries, sync vs async.
- Data model and ontology: what the unit is, what identity means, which entity
  is primary and which is derived, where each piece of truth lives.
- Contracts: API, event, file, or protocol shape between parts you own.
- Semantics under stress: ordering, idempotency, retries, partial failure,
  replay, backfill.
- Build vs buy, migration strategy (big-bang vs strangler vs parallel run).
- The user says "how should this work", "what's the right architecture",
  "how should A and B relate", or names two subsystems that should become one.

**Do NOT use when:**

- The ownership test fails. Pick and build.
- The user already specified the design. Build it.
- The options differ only in outcome — "should it retry or alert?" is
  `confused`.
- The options differ in how they look — that is `elicit-ui`.
- It is a vendor choice inside one design (Kafka vs RabbitMQ under the same
  topology). That is a sub-decision: a `confused` question or a round two.
- It is a bug fix wearing an architecture costume.

## Workflow

```
1. Pin facts   Research the domain; one confused round for facts that prune.
2. Inventory   Every responsibility, contract, and guarantee of today. Gate.
3. Diagnose    Run today's design through the bench. What actually breaks?
4. Floor       Pull out what every direction needs anyway. Not a choice.
5. Axis        Name the one structural conflict. One axis per deck.
6. Cut         Directions that disagree on mechanism. Default 5–8.
7. Bench       Same scenarios, same criteria, traced through every direction.
8. Argue       Ledger and verdict for each. One pick, runner-up, objection.
9. Publish     One artifact, graph first. Link, axis, pick, objection.
10. Build      The chosen design exactly. ADR, acceptance tests, vault note.
```

## 1. Pin the Facts That Prune

Some facts delete directions outright: volume, data access, deadlines,
regulation, existing infrastructure, appetite for new infrastructure. Find them
before designing anything.

- Investigate first: the repo, metrics, logs, configs, and **primary sources**
  for the domain — the regulation itself, the vendor's own docs. Link them in
  the deck; mark anything unconfirmed as *unverified*.
- Then one `confused` round for what investigation cannot settle.
- Record each answer as a **fixed consequence**, not as an answer:
  *"volume < 500k/day → stream processing is not a main direction"*. The deck
  shows them in a strip under the axis. Never re-ask them.
- **"Unknown" is an answer.** No direction may *depend* on an unknown. A
  direction that needs it becomes conditional, and says on what.

## 2. The Inventory Gate (non-negotiable for existing systems)

Enumerate what exists, mechanically, before proposing anything:

| Kind | Enumerate |
|---|---|
| Entry points | routes, CLIs, timers, consumers, webhooks, file drops, pollers |
| State | every store, and **who writes it** — two writers is a finding |
| Messages | topics and queues, producer, consumers, partition key |
| Contracts | every API consumed or provided, every file format exchanged |
| Guarantees | ordering, idempotency, delivery, auth boundaries, retention, audit — including the ones nobody wrote down that something relies on |
| Operations | deployables, alerts, dashboards, backups, secrets (by name only) |

```bash
rg -n '@(Get|Post|Put|Delete|Request)Mapping|router\.(get|post|put|delete)'
rg -n '@(Kafka|Rabbit|Sqs|Jms)Listener|\.subscribe\('
rg -n 'CREATE TABLE|@Entity|@Table'
systemctl list-timers --all; docker compose config --services
```

Then:

- **Ship it as a matrix:** inventory item × direction → *kept*, *moved to X*,
  *merged into Y*, or **given up**. The user must be able to audit you.
- **Grouping is a proposal; removal is a regression.** Folding four engines
  into one module is a direction. A guarantee that silently stops holding is a
  bug you will be caught on.
- Anything a direction drops goes into its `gives up` row, in words.
- **Greenfield:** the inventory is the requirements and constraints. Each
  direction states how it meets each one.

## 3. Diagnose Today

Before proposing anything, run the current design through the bench (§7). It
becomes a pinned **Today** row in every comparison — the baseline the
directions must beat, never ranked against them.

This is often where most of the value is: the hidden dual write, the partition
key that loses per-entity ordering, the "webhook receiver" that is only a
third of the inbound traffic. Write each finding as one line with the scenario
that exposes it.

## 4. The Floor

Some things every direction needs: idempotency keys, a schema registry, an
outbox, tracing, a shared calendar library. They are not choices.

List them once, as **the floor**, show them once, and strip them from every
direction. Otherwise each direction appears to differ on twenty things and the
deck carries no information. A diagnosis finding that every direction fixes
belongs here, not on the axis.

## 5. Name the Axis

One sentence, before any direction exists. It is almost always one of:

- Where does the truth live?
- Who coordinates the transitions?
- What is the unit — what has identity, what is derived?
- What is coupled in time?
- What do we own, and what do we rent?

> *"Where does the truth about a record's state live, and who coordinates its
> transitions?"*

Every direction answers the axis in **one line**. Those lines are the table
at the top of the deck.

**One axis per deck.** If the pick needs two independent answers, there were
two axes: pick on the first, run a round two on the second. The lineage deck
picked a topology and deliberately left coordination for round two.

## 6. Cutting the Directions

They must **disagree on mechanism**, not on vendor. Two directions that differ
only in which broker or which cloud are one direction shown twice.

| Axis | Example poles |
|---|---|
| Topology | library · modular monolith · services · functions · bought platform |
| Truth | one database · database per service · event log · the external system |
| Coordination | in-process · choreography · orchestrator · durable workflow · batch |
| Coupling in time | sync call · async message · file/batch · CDC |
| Unit | entity-primary · event-primary · document-primary · graph |
| Ownership | build · managed service · vendor product |
| Risk | closest to today ↔ complete reframe |

Rules:

- One **conservative** direction (closest to today) and one **most
  distinctive**. Include the **buy** pole whenever a credible product exists.
- No two directions give the same one-line answer to the axis.
- Names a person would say — *The log is the truth*, *One core, many
  replicas*, *Buy the bus* — never *Option C*.
- Never include a direction you would refuse to build.
- Round one is a **probe, not a verdict**. The likely round two merges the
  pick with the best organs of the runners-up — design the deck so a merge is
  easy to draw.

## 7. The Bench — the Same Questions to Every Direction

This is the interactivity bar. A deck the user can only read is a document.
The user must be able to drive all of:

**Scenarios (5–8).** Each is traced step by step on the direction's own
diagram: where the work is, what is persisted, what is waiting. Source them
from history before imagination — incident notes in the vault, fix commits,
outages, the roadmap's next item. Always include:

| Scenario | Exposes |
|---|---|
| The happy path | the moving parts and hops |
| The worst realistic failure | partial failure mid-flow, duplicate delivery, a dependency down for hours |
| Recovery | replay, backfill, the dead-letter path, a restore |
| The most likely next change | the Nth integration, a new field, a new tenant |
| A scale step | ×10 load, or the busiest hour of the year |
| Six months later | a new person debugging it at 3 a.m. — where do they look? |

Every scenario ends in one outcome per direction: **handled**, **degraded**,
**wrong state**, or **needs a human**. Glyph plus word, never colour alone.

**Change cost.** For each anticipated change, highlight on the diagram every
box that must change, and count the deployables and modules touched.

**Criteria weights.** The user's criteria as sliders. The score matrix
re-ranks live. Every score is 1–5 with a one-line justification that cites a
scenario step or a number.

**Numbers.** Latency, throughput, cost, effort — as ranges, with their
assumptions beside them. **Measure what decides it:** when a direction's
viability hinges on a number a short spike can produce — database throughput
on the target hardware, a library's behaviour under a given failure, a vendor's
rate limit — run the spike, and put the measured number, the method, and the
command in the deck. Heavy spikes go through `cage`; GPU work through
`gpu-lock`.

**Type sketch.** For data-model and ontology decisions, the core types or the
schema of each direction, 10–25 lines. Here the types *are* the specimen —
what the device frame is to `elicit-ui`.

A score you cannot trace to a scenario step or a measured number is an
opinion. Mark it as one.

## 8. Real Data

Real volumes, real entity names, real table and topic names, real incidents,
real deadlines, real stack. Read them from the source of truth.

| Content | Do |
|---|---|
| No repo or metrics access | Assume, and **label every assumption** in the deck footer |
| Secrets, credentials, `.env` | By name only. Never read `secrets/`. Never. |
| Employer or client specifics | Fine in the private artifact; never in the public repo or vault |
| Personal data in samples | Synthesise, deterministic per ID, and say so |

An unlabelled assumption is a number the user will quote in a meeting.

## 9. The Ledger and the Verdict

Every direction carries the same six rows, in the same order, so they compare
by scanning one column:

| Row | Contents |
|---|---|
| `touches` | which deployables, modules, and contracts change |
| `adds` | new primitives and infrastructure, rough size |
| `removes` | what stops existing — usually the good news |
| `operates` | what someone runs, pages on, patches, and pays for, every month |
| `gives up` | the honest cost, in the user's terms |
| `undo` | what backing out costs a year from now — one-way or two-way door |

The verdict is one short paragraph that **takes a position**: recommend,
mixed, or against. Mark exactly one pick and say why, name the runner-up and
what fact would make it win instead, and state the strongest objection to your
own pick. Argue against your weak directions — a deck in which every option
sounds good carries no information.

## 10. Publishing — Graph First

One artifact, all directions, via the Artifact tool. Load `artifact-design`
first; the build recipe is `reference/trace-kernel.md`.

- **The diagram is the first and largest thing** in every direction. Prose is
  capped at three sentences per direction. Everything else is diagram, bench,
  ledger, numbers.
- **One layout grammar for all directions** — the same lanes, external
  systems in the same place — so switching directions shows what moved, not a
  reshuffle.
- Mark where the truth lives (★) for every key entity, on every diagram.
- Switching direction **keeps the selected scenario and step**. That is the
  comparison.
- Order: axis table and fixed-consequence strip → Today's diagnosis →
  directions (opens on the pick) → bench matrix with weights → inventory
  matrix → the floor → assumptions and sources.

Hand over: the link, the axis, the pick with its one-line reason, the
strongest objection to it, and the round-two question, if there is one.

## 11. After the Pick

- Build the chosen design **exactly**. The deck was a contract. If something
  in it turns out to be impossible, stop and say so before building — never
  substitute silently.
- Write an ADR per decision: context, axis, directions considered, the pick,
  and the `gives up` and `undo` rows verbatim as accepted consequences. In the
  project's `docs/adr/` if it has one, otherwise `~/Projects/<name>/docs/adr/`.
- The pick's traced scenarios are its **acceptance tests**. Each becomes a
  test, a chaos drill, or a runbook step.
- An open sub-decision gets a round-two deck scoped to it — or a `confused`
  question, if its options differ only in outcome.
- Save the *why* to the vault. Never put employer or client specifics there;
  it is public.

## Critical Rules

1. **Trace, never argue.** If it is about how something works, the options are
   drawn and run through the same scenarios. A pros-and-cons list is the
   failure this skill exists to prevent.
2. **Pass the ownership test**, or pick the mechanism yourself.
3. **Inventory first.** Never redesign a system you have not enumerated. Ship
   the enumeration.
4. **Never drop a guarantee silently.** Anything given up is named, in words.
5. **One axis per deck.** Factor out the floor. Vendors are not directions.
6. **Graph first.** Three sentences of prose per direction, at most.
7. **Measure what decides it.** Label every assumption.
8. **Take a position.** One pick, one runner-up, one honest objection.
9. **Build exactly what was chosen.** No silent substitutions, ever.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Pros-and-cons prose for each option | Draw them; trace the bench through each. |
| Directions that differ only by vendor or cloud | Re-cut along the axis. The vendor is a round two. |
| Every direction carries the same twenty good practices | Move them to the floor; show them once. |
| A deck that needs two picks | There were two axes. Split into rounds. |
| Scenarios invented, history ignored | Start from incidents, fix commits, and the roadmap. |
| Scores with no justification | Cite the scenario step or the number, or mark it opinion. |
| Today never diagnosed | Run the current design through the bench first. |
| A direction quietly loses a guarantee | Inventory gate; the `gives up` row. |
| Asking which architecture they prefer, in text | Text asks outcomes. Mechanisms the user owns get traced. |
| Eliciting a mechanism that fails the ownership test | Pick it, build it, say what you picked. |
| Building "basically" the pick | Build exactly it, or say why you cannot. |
