---
name: confused
description: Use when a request has more than one defensible reading and guessing wrong would waste real work — vague asks ("make it better", "fix the thing"), a fork with no obvious default, or a scope/blast-radius call that cannot be settled from the repo. Elicits intent through multiple-choice questions whose stems name objectives and whose options name consequences. Also pulled mid rebuild+switch (mandragora-switch, mandragora-wsl-switch) when the switch aborts or forks and the recovery path is a judgement call. Triggered explicitly via /confused.
---

# confused — Resolve Intent Before Spending Work

## Overview

Ambiguity is cheap to resolve and expensive to guess. This skill converts
"I don't know what you want" into a small set of multiple-choice questions
the user can answer in seconds, without knowing anything about the
implementation.

**The two laws:**

1. **Questions are objectives.** The stem asks what the user is trying to
   achieve. It never asks which mechanism to use.
2. **Options are consequences.** Each choice states the world after that
   choice — what becomes true, what is given up, what it costs. It never
   states the approach that produces it.

The user is the authority on *what should be true*. You are the authority
on *how to make it true*. Every question that crosses that line is the
wrong question.

## When to Use

- Request admits two or more readings that lead to materially different work.
- A fork appeared mid-task and neither branch is a clearly reasonable default.
- Scope is unbounded ("clean this up", "make it faster") and the blast radius
  is the actual decision.
- A rebuild+switch aborted and recovery is a judgement call (see
  **Rebuild+Switch Mode**).
- The user typed `/confused`.

**Do NOT use when:**

- The answer is discoverable. Run the command, read the file, check the log.
  AGENTS.md execution discipline outranks this skill: investigate first,
  ask only about what investigation cannot settle.
- One reading is clearly reasonable. Per AGENTS.md decision discipline, take
  it, do the work, and say which reading you took. Redirection in flight is
  cheaper than an interruption.
- The choice is reversible and cheap. Just pick.
- You are asking for permission rather than information. Permission questions
  belong in the risky-action gate, not here.
- The user already answered. Re-asking a settled question reads as not
  listening.

## Workflow

```
1. Investigate  Exhaust what you can determine yourself. Read, grep, run.
                Every fact you find is a question you don't have to ask.
2. Enumerate    List every remaining unknown.
3. Prune        Drop each unknown whose answer would not change the work.
                (Stopping rule, below.) Usually kills half the list.
4. Rank         Order survivors by how much of the rest they invalidate.
                Widest fork first.
5. Ask          One AskUserQuestion round, <=4 questions, 2-4 options each.
                Only independent questions share a round.
6. Contract     Restate the resolved spec in <=5 lines. Name assumptions
                for anything still unasked.
7. Build        Act on the contract. Do not re-ask.
```

## Writing the Question (objective framing)

The stem names the goal at stake, in the user's vocabulary.

| Bad (mechanism) | Good (objective) |
|---|---|
| "systemd timer or cron?" | "What should happen when a sync falls behind?" |
| "Should I use a worktree?" | "Should this land on master today, or park until reviewed?" |
| "Refactor into a module?" | "Who else needs to reuse this — just here, or every host?" |
| "Pin the flake input?" | "When upstream breaks this, should it break loudly or stay frozen?" |
| "Which file should it go in?" | (Not a question. Pick a file.) |

Rules:

- One decision per question. If the stem contains "and", it is two questions.
- Use the user's words. If they said "the thing", ask about "the thing" —
  do not silently rename it to `nix/modules/user/services.nix`.
- Never ask a question whose answer you would override anyway.
- `header` is <=12 chars and names the axis, not the answer: `Scope`,
  `Blast radius`, `On failure`, `Done when`.

## Writing the Options (consequence framing)

Each option is the **end state**, not the route to it.

- `label` (1-5 words): the outcome.
- `description`: what becomes true, what is lost, what it costs. State the
  downside explicitly — an option with no stated cost reads as the free one
  and skews the answer.

**The consequence test.** Delete from the option every proper noun that
names a tool, file, function, or flag. If nothing decision-relevant remains,
the option described mechanism and must be rewritten.

```
FAIL  "Use a systemd path unit"        -> strip nouns -> "Use a"
PASS  "Reacts within a second"
       "Fires on every write, including the ones mid-edit.
        Costs a wakeup per change; no polling delay."
```

More rules:

- 2-4 options. Fewer than 2 is not a question; more than 4 is a menu.
- Options must be mutually exclusive unless `multiSelect: true`.
- Order by your recommendation. Put the recommended one first and append
  "(Recommended)" to its label — a recommendation is not a bias, withholding
  one is.
- Never write "Other" — the tool adds it. But do leave the real escape open:
  if none of your options fit, that is a signal you framed the axis wrong.
- Cover the space. If a plausible outcome is missing, the user is forced into
  the closest wrong answer.

## Rounds and the Stopping Rule

**Stopping rule:** keep a question only if at least two of its answers would
produce visibly different work. If every answer leads to the same diff, you
already know enough — proceed and state the assumption.

- Round 1: the independent, widest forks (up to 4).
- Round 2: only questions that round 1 made relevant. Answers often delete
  half of them.
- Hard cap: 3 rounds. Past that you are interrogating, not eliciting. Take
  the most defensible reading, state it, and build.

If the user picks "Other", take it literally and move on. Do not re-ask the
same question reworded — that is how a clarification becomes an argument.

## Rebuild+Switch Mode

`mandragora-switch` (desktop) and `mandragora-wsl-switch` (WSL) abort in ways
whose recovery is a real judgement call. When one of those aborts, this skill
turns the failure into a choice instead of a wall of stderr.

Applies to these switch outcomes:

| Abort | Objective to ask about |
|---|---|
| "main tree is publish-only" | Whose changes should be in this commit? |
| Repo audit failed | Is this failure yours to fix, or pre-existing? (Rule 18 default is isolate) |
| `mandragora-wsl` eval failed in pre-flight | Should the other host block this switch? |
| Rebase conflict on promote/push | Should your commit go on top, or wait? |
| Activated but units failed | Ship the generation, or roll back? |
| Heavy source build in `--dry-run` | Rule 19 — park it, or cage it and pay the RAM? |

Two hard limits in this mode:

1. **Never turn a non-negotiable into an option.** Rules 10, 18, and 19 are
   already decided. Asking "should I bypass audit?" launders a violation into
   a user choice. Report the rule and the isolation default instead.
2. **Never ask mid-activation.** If `nixos-rebuild switch` is running, wait
   for it to land. A question answered against a half-applied generation is
   answered against a system state that no longer exists.

Worked example — the publish-only abort:

```
Q  header: "Commit scope"
   "The main tree has changes from more than one session. What should
    land in this commit?"

1  "Only my changes (Recommended)"
   Your files commit and build; everything else stays dirty exactly as
   it is. Another session's work is never attributed to you. Costs one
   worktree and about ten seconds.

2  "Everything currently dirty"
   One commit sweeps all pending work across sessions, including files
   you never touched, under one message. Fast now; the history is
   misleading later and a revert takes unrelated work with it.

3  "Nothing — build without committing"
   You see whether it builds; nothing is recorded and nothing is pushed.
   The decision comes back the moment you want it on another host.
```

Every option names an end state. None names a git command.

## Critical Rules

1. **Investigate before asking.** A question you could have answered with
   `grep` is a question that spends the user's attention on your laziness.
2. **Never ask about mechanism.** Naming, file placement, and equivalent
   approaches are yours to decide (AGENTS.md decision discipline).
3. **Always state the cost.** A consequence with no downside is marketing.
4. **Recommend.** First option, "(Recommended)" suffix. Neutrality on a
   question you have an informed view about is not helpful, it is evasive.
5. **Never re-ask.** An answer, including "Other", is final for the session.
6. **Never smuggle a rule into a vote.** Non-negotiables are not options.
7. **Contract before building.** <=5 lines: what you will do, what you will
   not touch, what you assumed. Then build without further questions.

## Common Mistakes

| Mistake | Fix |
|---|---|
| "Which approach do you prefer?" | Ask what outcome they need; you pick the approach. |
| Options are tool names | Apply the consequence test. Strip the nouns. |
| Every option sounds good | You omitted the costs. Each needs its downside. |
| 6 questions in one round | Prune by the stopping rule, then rank; ask <=4. |
| Asking what the repo already says | Read the repo. |
| Asking permission to do the obvious thing | Do it, report it. |
| Re-asking after "Other" | Take it literally and proceed. |
| Question chains that never terminate | 3 rounds max, then state assumptions and build. |
