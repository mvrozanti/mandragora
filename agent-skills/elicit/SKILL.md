---
name: elicit
description: Use before consequential work when you need to know what the user actually wants the finished result to do — a goal with no stated done-state ("scrub X", "make it reliable", "move this to the VPS"), an obvious path with side effects the user may not foresee, or any one-way door. Asks behavior → consequence checks as multi-select questions; the user ticks the behaviors they want, the ticks become the contract and the acceptance tests, and everything unticked is out of scope. Questions only — never an artifact, deck, or diagram (that is elicit-ui). Triggered explicitly via /elicit.
---

# elicit — Behavior → Consequence Checks

## Overview

You understand what the user wants when you can predict which observable
behaviors of the finished work they would accept and which they would reject.
This skill finds out by asking: each **check** is one concrete behavior paired
with the consequence it carries. The user ticks the ones they want.

- What they tick is the spec, and later the acceptance test.
- What they leave unticked is out of scope. Don't build it.
- The consequences attached to ticked checks are costs they accepted, so you
  never have to ask about them again.

The user owns behavior. You own mechanism. A check never names a mechanism.

**elicit asks. It never draws.** No artifact, no deck, no diagram, no
"directions". If you are about to publish something under `/elicit`, stop:
that is `elicit-ui`.

## Which Skill

| What is open | Skill | Instrument |
|---|---|---|
| What the finished work should do, and which costs are acceptable | **`elicit`** | behavior → consequence checks, multi-select |
| Which of two or three readings the user meant | `confused` | one question per fork, end-state options, single pick |
| How it should look | `elicit-ui` | one published artifact of working directions |

`elicit` and `confused` are both text. `confused` resolves a fork: pick one end
state. `elicit` maps the whole done-state: tick every behavior you want, see
what each one costs. An elicit round often surfaces two ticked checks that
can't both hold. That conflict is then one `confused` question.

## When to Use

- The request names a goal but not the done-state.
- The obvious path has side effects the user probably didn't foresee: guards
  that will refuse, links that break, other agents or people affected,
  something that becomes irreversible.
- A one-way door: history rewrites, deletions, public changes, data
  migrations, anything pushed.
- The user typed `/elicit`.

**Do NOT use when:**

- The user already stated the behaviors. Build them.
- One reading is obviously right and the change is reversible. Do it, say
  which reading you took (AGENTS.md decision discipline).
- What's open is a single fork. Use `confused`.
- What's open is how it looks. Use `elicit-ui`.

## Workflow

```
1. Investigate  Read, grep, run, measure. Every fact you find is a check you
                don't have to ask, and every consequence needs a real number
                or a real name from this step.
2. Behaviors    List everything observable that could be true when the work is
                done: what the user asked for AND the side effects of getting
                there.
3. Consequences Pair each behavior with what it costs, breaks, rules out, or
                makes irreversible. Specific and measured.
4. Prune        Keep a check only if ticking or unticking it changes the work.
                A behavior that holds on every path is a given, not a check:
                state it in the contract.
5. Group        By theme, 2-4 checks per question, multiSelect. Header names
                the theme (Reach, Safety, Afterwards, Undo).
6. Ask          One round, every group. AskUserQuestion takes four questions
                per call; more groups mean consecutive calls.
7. Reconcile    Two ticked checks that can't both hold: one confused-style
                question per conflict. An unticked side effect that every
                path forces: say so, and ask once whether to stop.
8. Contract     Three lists, <=10 lines: Will be true / Will not be done /
                Costs accepted.
9. Build        Exactly the contract. Then verify every ticked behavior and
                report each one as pass or fail.
```

## Writing a Check

- **label**: the behavior, 1-5 words, observable, in the user's vocabulary.
- **description**: `→ ` then the consequence. Lead with the cost. Use the
  numbers from step 1.

**The behavior test.** Could the user verify it after you are done, without
reading code? "Fresh clones carry no BMAD" passes. "Use filter-repo" fails:
that is mechanism, and mechanism is yours.

**The consequence test.** A check with no cost is marketing. If a behavior is
genuinely free, it is a given, not a check.

```
Q  header: "Reach"   multiSelect
   "Where should BMAD be gone from when this is done?"

[ ] Fresh clones carry no BMAD (Recommended)
    → every commit hash since Apr 20 changes (2,447 commits); 38 vault
      notes then cite hashes that no longer exist
[ ] Old GitHub links stop working
    → only possible by deleting and recreating the repo: 5 stars, issue #1
      and PRs #2-4 lost, and the fork blocks any restore
[ ] Gource stops showing it
    → 7 cached videos re-render; nothing else changes
```

Rules:

- One behavior per check. If the label needs "and", split it.
- Checks in one question are independent: any combination of ticks must be
  meaningful. Outcomes that exclude each other are a `confused` question.
- **Show the side effects.** The checks the user would never think to ask
  about ("the next switch is refused until you type your sudo password") are
  the reason this skill exists. A side effect that every path forces is still
  shown, as something to accept. Unticked means stop and talk.
- Recommend. Put the checks you'd tick first, with "(Recommended)" on the
  label.
- Never put a non-negotiable in a check. AGENTS.md rules are not options.

## Rounds

- Round 1: every group.
- Round 2: only conflicts and refused side effects.
- Cap: 3 rounds. After that, state the most defensible reading and build.

An answer is final. "Other" is taken literally and never re-asked.

## Critical Rules

1. **Ask, never draw.** No artifact, deck, or diagram under `/elicit`.
2. **Investigate first.** Every consequence carries a measured number or a
   named thing.
3. **Behaviors are observable; mechanisms are yours.**
4. **Every check states its cost.**
5. **Show the side effects**, not just what was asked for.
6. **Ticked is the contract. Unticked is a non-goal.** Never build an
   unticked behavior.
7. **Verify every ticked behavior after building**, and report each one.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Publishing an artifact, deck, or diagram | That is `elicit-ui`. Ask in text. |
| "Which approach do you prefer?" | Ask which behaviors they want; you pick the approach. |
| Checks with no cost | Add the consequence, or make it a given. |
| Only listing what they asked for | Add the side effects. |
| Mutually exclusive checks in one multi-select | Make it a `confused` question. |
| Building something unticked | Unticked is a non-goal. |
| Ending without checking the ticked behaviors | They are the acceptance tests. Run them. |
