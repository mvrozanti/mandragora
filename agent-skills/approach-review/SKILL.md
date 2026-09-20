---
name: approach-review
description: Pause and critically evaluate the current approach before continuing work. Use when a task is complex, consequential, ambiguous, unexpectedly difficult, accumulating complexity, producing repeated failures, or when new information may invalidate the current plan. Also use proactively at meaningful milestones, before committing to a large implementation, or whenever the current path feels like it may be solving the wrong problem. This skill is about improving the approach, not exposing private chain-of-thought.
---

# Approach Review

## Purpose

Temporarily stop execution and evaluate whether the current approach is still
the right one.

The goal is not to produce more reasoning for its own sake. The goal is to
catch:

* solving the wrong problem
* unnecessary complexity
* invalid assumptions
* premature implementation
* inefficient workflows
* repeated failed attempts
* missed tools, capabilities, or simpler alternatives
* plans that made sense initially but no longer fit the evidence
* local optimizations that make the overall solution worse

After the review, either continue, adjust the approach, or ask the user for
clarification if the objective itself is uncertain.

Do not expose private chain-of-thought. Summarize conclusions, assumptions,
tradeoffs, and decisions at a useful level.

## When to Activate

Activate this skill when one or more of the following are true.

### Before substantial commitment

Pause before:

* implementing a large feature
* making broad changes across a codebase
* choosing an architecture
* introducing a new dependency or service
* performing an irreversible or expensive operation
* creating a long multi-step workflow
* committing to an interpretation of an ambiguous requirement

### When execution is going poorly

Pause when:

* the same approach has failed more than once
* fixes are creating new problems
* the implementation is becoming unexpectedly complicated
* progress requires increasingly awkward workarounds
* assumptions keep being discovered after implementation
* the agent is repeatedly undoing and redoing work
* a test, tool, or external result contradicts the plan

### When new information arrives

Pause when:

* the user changes or clarifies the objective
* new constraints surface that the plan never accounted for
* a file, log, or command output contradicts a load-bearing assumption
* an upstream change invalidates part of the work already done
* a simpler capability turns out to already exist
* the cost of the chosen path turns out to be much higher than estimated

### At meaningful milestones

Pause when:

* a phase of a multi-step plan completes
* the work is about to cross from exploration into implementation
* the remaining work is about to exceed what was originally scoped

## When NOT to Activate

This skill is a course correction, not a ritual. Skip it when:

* the task is small, reversible, and going fine — just do it
* you already reviewed this approach and nothing has changed since
* the "review" would only restate the plan back to the user
* you are looking for permission rather than for a better path.
  Execution discipline outranks this skill: if the work is in-scope and
  reversible, act. A review that terminates in "should I continue?" has
  failed.
* the uncertainty is factual and discoverable. Run the command, read the
  file, check the log. Investigation beats deliberation.

Reviewing too often is its own failure mode: it converts working time into
meta-work and reads as hesitation. Two or three reviews in a long task is
healthy; one per turn is a stall.

## Procedure

```
1. State the objective     What is the user actually trying to achieve?
                           In their words, not the plan's vocabulary.
2. State the current path   One or two lines. If it cannot be stated that
                           briefly, that is itself the finding.
3. List the assumptions    Every belief the path depends on. Mark each
                           VERIFIED / UNVERIFIED / CONTRADICTED.
4. Verify the cheap ones   Any UNVERIFIED assumption a command can settle
                           in seconds gets settled now, not reasoned about.
5. Look for the simpler    Is there an existing tool, capability, file, or
   path                    one-step version that reaches the objective?
6. Check the failure       If attempts have failed, what do the failures
   pattern                 have in common? Treat that as the real problem.
7. Decide                  CONTINUE, ADJUST, RESTART, or CLARIFY.
8. Act                     Execute the decision in the same turn.
```

## The four verdicts

| Verdict | Meaning | Next action |
|---|---|---|
| **CONTINUE** | Path is still the best available; assumptions held up. | Resume immediately. Say so in one line; do not re-explain the plan. |
| **ADJUST** | Objective is right, route is wrong. | Change the route and keep going. No approval needed for reversible work. |
| **RESTART** | The work so far is solving the wrong problem. | Say what was wrong, discard or park the work, start the correct path. |
| **CLARIFY** | The *objective* itself is genuinely ambiguous. | Hand off to `confused` — one round of objective-framed multiple choice — then build. |

Only **CLARIFY** goes back to the user, and only when the ambiguity is about
what should be true, not about how to make it true.

## Diagnostic questions

Run these against the current work. Each one has caught a real failure.

**Problem framing**

* What would "done" look like to the user — not to the plan?
* Am I solving the problem they have, or the one that is easier to state?
* If this succeeds perfectly, does it actually help?

**Assumptions**

* Which belief, if false, would waste the most work? Is it verified?
* What am I taking from memory or a prior session that may have gone stale?
* Did I confirm a file/flag/endpoint exists, or infer that it does?

**Complexity**

* What is the simplest thing that could possibly work?
* Which part of this design exists only to support another part of this
  design? That is often removable in a pair.
* Could this be a smaller change to something that already exists?

**Failure pattern**

* What do the failed attempts have in common?
* Am I fixing symptoms in sequence instead of one cause?
* Have I attacked the same wall twice? A third attempt needs a different
  angle, not more force.

**Cost**

* Is the remaining effort proportionate to the value?
* Is there an irreversible step coming, and is it justified yet?
* Am I optimizing something local at the cost of the whole?

## Output format

Keep it short and decision-shaped. The user reads a verdict, not a
deliberation.

```
Approach review — <what is being reviewed>

Objective   <one line, user's framing>
Path        <one line, current route>
Findings    <1-4 bullets: assumption broken, simpler route found,
             repeated-failure cause, scope drift — with evidence>
Verdict     CONTINUE | ADJUST | RESTART | CLARIFY
Next        <what happens now, already underway>
```

Rules for the report:

* Every finding cites something checkable — a command's output, a file, a
  contradiction. A finding with no evidence is a vibe.
* No chain-of-thought. Conclusions and tradeoffs only.
* Never end on a question unless the verdict is CLARIFY.
* If the verdict is CONTINUE, three lines is a complete review.

## Interaction with the other skills

* `confused` — the CLARIFY hand-off. Use it whenever the ambiguity is about
  the objective. This skill reviews the route; `confused` resolves the goal.
* `elicit-ui` — if the fork under review is visual, options must be shown,
  not listed.
* `nrp` — a review that finds the work has sprawled into unrelated concerns
  ends in `nrp`, splitting the diff by topic before commit.
* `handoff` — a RESTART verdict late in a session is worth writing down; the
  next agent should not re-walk the discarded path.

## Critical rules

1. **Terminate in an action, not a question.** The default verdict is
   CONTINUE and the default next step is "keep working".
2. **Verify before you reason.** Any assumption a command can settle gets
   settled by the command.
3. **A second identical failure is the trigger, not the third.** Repeating
   an approach that already failed is the most expensive mistake available.
4. **Sunk work is not evidence.** How much has been built says nothing about
   whether it is the right thing to build.
5. **Don't review the review.** One pass, one verdict, back to work.
6. **Never launder a rule into a finding.** Non-negotiables are not up for
   re-evaluation here.
7. **Name what you were wrong about, once.** Plainly, in a line, then move
   on. No post-mortem essay, no apology.

## Common mistakes

| Mistake | Fix |
|---|---|
| Review ends with "want me to proceed?" | Proceed. Report after. |
| Reviewing every turn | Review at commitments, failures, and new information — nothing else. |
| Findings with no evidence | Cite the output, file, or contradiction. Otherwise drop it. |
| Restating the plan as a "review" | A review that changes nothing and finds nothing is noise; say CONTINUE in one line. |
| Reasoning about a question `ls` would answer | Run `ls`. |
| Treating built work as a reason to keep going | Judge the path forward, not the path behind. |
| RESTART with no record | Write the dead end down so it is not re-walked. |
