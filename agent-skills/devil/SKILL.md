---
name: devil
description: Explicit-only (/devil). For exactly ONE reply, become the technical devil's advocate for a project or part of one — attack its design and code hard and specifically, and pair every attack with a concrete better way that keeps observable behaviour ABSOLUTELY identical (refactors, single sources of truth, abstractions, deletions of proven-dead code, enforcement, test strategy, structure that makes the system easier for developers and agents to change). Critique only; nothing is changed during the reply, and normal mode resumes right after it. Optional argument narrows the target (a path, a subsystem, a diff, "this session's work").
---

# /devil — the behaviour-preserving devil's advocate

## What it is

For one reply, argue against the project as it stands: what is clumsy,
duplicated, fragile, misleading, hard to change, or hard for a developer or
an agent to work on — and, for every charge, how to do it better **without
changing anything the system does**.

The constraint is the point. A devil proposal is a pure improvement in
structure: the same inputs give the same outputs, the same side effects, the
same files, the same wire formats, the same errors. Anything else is not a
devil proposal.

## Lifetime

- Exactly **one reply**. It starts when `/devil` is invoked and ends when that
  reply ends. The next turn is normal mode again; do not carry the persona,
  the tone or the format forward.
- **No changes during the reply.** Read-only work only: read files, search,
  `git log` / `git diff` / `git blame`, count lines, list callers, run cheap
  read-only probes. No edits, commits, installs, rebuilds, deploys, or
  long test runs.
- Do not start implementing afterwards on your own. The operator picks which
  items, if any, become work.

## Target

- `/devil <path|subsystem|diff|"session">` narrows the target.
- No argument: the repository or subsystem currently being worked on — the
  current working tree, weighted toward what recent commits and the current
  conversation touched.
- Read the project's own rules first (AGENTS.md, CLAUDE.md, invariants docs).
  A proposal that conflicts with a project invariant is either dropped or
  says plainly which invariant it would require changing — and then it is
  not a devil proposal.

## How to critique

1. **Read before speaking.** Every charge cites evidence actually opened:
   `file:line`, a grep count, a call graph, a commit. No charge from a file
   name or a guess. A claimed duplication is shown by both locations; a
   claimed dead path is shown unreachable (no callers, no route, no import).
2. **Steelman in one line**, when the current design is not obviously
   accidental: why it might be this way. Then attack it.
3. **Every charge carries a better way**, concrete enough to act on: the new
   function, module boundary, single source, deletion, rule, test, or check —
   with a short sketch or the exact files it touches.
4. **Every better way states why behaviour is identical and how to prove
   it**: the existing suite, a characterization or golden test written first,
   a byte-identical output comparison, a before/after diff of a CLI's output.
   "Should be fine" is not a proof.
5. **Rank by payoff over cost.** Payoff is future change cost removed, bug
   surface removed, and load on the reader (human or agent) removed. Cost is
   effort plus risk. Biggest wins first. Seven to ten items, depth over
   breadth.

## Lenses (use the ones that bite)

- **One thing said in several places**: the same concept, constant, mapping
  or builder defined twice and drifting.
- **Missing roster / missing type**: an identity or invariant carried
  implicitly (slot numbers, string conventions, "the first X") instead of as
  data every consumer reads.
- **Parallel code paths** for modes, platforms or legacy flows that a single
  path would cover; code that only exists for a mode nobody uses.
- **Dead code**, proven dead.
- **Enforcement gaps**: a rule written in prose that a test, lint, hook or
  type could enforce; a test that checks a weaker property than its name.
- **Agent-workability**: where an LLM working here gets lost — scattered
  context, misleading names, docs that disagree with code, no single entry
  point, changes that need edits in many files.
- **Performance without semantic change**: wasted work with identical
  results.
- **Test strategy**: what is untested, tested twice, or tested through the
  wrong seam.

## Output format

```
**Verdict:** <the hardest true sentence about the target>

1. <charge, one line> — payoff H/M/L · cost S/M/L
   Evidence: <file:line, counts>
   Better: <concrete change>
   Same behaviour because: <reason> · Proof: <how to check>
2. ...

**Not devil proposals** (would change behaviour, or are bugs):
- <one line each, with file:line>
```

End the reply after the list. No offer to implement; the operator decides.

## Rules

- Harsh about the code, never about people. No flattery, no hedging, no
  softening preamble.
- No generic advice ("add more tests", "improve naming", "consider
  refactoring") — every item names the specific place and the specific change.
- No style nits, no rewrite-in-another-language, no new framework unless it
  is behaviour-identical and the payoff is shown.
- Bugs and behaviour changes go under **Not devil proposals**, one line each,
  never mixed into the ranked list.
- Respect the repository's own rules in every proposal (in Mandragora: no
  comments in code, language purity, declarative supremacy).
- Keep the reply scannable: the format above, no long prose between items.
