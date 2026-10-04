---
name: minify
description: Use when a project has grown hard to change — a small request turns into a sprawling plan, the same idea lives in several places that disagree, agents keep getting lost in or re-breaking one area, or the operator says "this is all so extensive", "minify this", "the code needs abstractions/enforcement", "clean this up so you can work on it". Finds where one concept is implemented several times, proposes the smallest refactor that makes the pending change small, and adds checks that keep it that way. Behaviour stays identical unless the operator decides otherwise. Project-scoped and structural; the built-in /simplify is the diff-scoped cleanup. Triggered explicitly via /minify.
---

# minify — make the next change small

## The law

A change is big because one idea is said in several places that disagree.
Find those places, give each idea one home, enforce it, then make the change.
Behaviour stays exactly the same unless the operator chooses otherwise.

Origin: slither-io-simulator, 2026-10-02. "Show every species in one world"
became a forty-file plan. The cause was not the feature: one world had two
builders that had drifted apart (wrong observation scale, a random world size),
"which snake is whose" had four sources, the page had two parallel modes, and an
env flag meant both "controlled" and "pack". Fixing those first made the feature
small.

## When

- a request the operator calls easy produced a long plan or touched many files
- the same area breaks again after being "fixed", or agents get lost in it
- adding one thing means editing N parallel paths in the same way
- the operator asks to minify, simplify the project, add abstractions or rules

Not for: cosmetic cleanup of a diff (use /simplify), or a redesign that changes
what users see (that is a behaviour decision; ask).

## Procedure

1. **Name the trigger.** Write down the change that felt too big. Everything is
   judged by whether it makes THAT change small.
2. **Map before reading.** For each concept the trigger touches, list every
   place it is defined, built or derived (grep constructors, flag names, field
   names). Wide repos: fan out read-only search agents in parallel and keep only
   their conclusions.
3. **Sort what you find into the five smells.**
   - *Two builders for one thing*: two code paths construct the same object;
     they drift. One function, every caller uses it.
   - *Identity without a source*: "which X is this" derived differently in
     several places (a global, an index, a lookup, "the first one"). One data
     type carries it; consumers read it and never derive it.
   - *Parallel modes*: two modes with parallel copies of the same features.
     Delete one. If users can see it, ask first.
   - *One flag, two meanings*: a switch that conflates concepts, so a new
     combination cannot be expressed. Split it into per-concept options whose
     defaults reproduce today exactly.
   - *Dead code*: unreachable paths, painters with no element, files no entry
     point loads. Prove it unreachable (grep plus the suite), then delete.
4. **Cut to the path.** Fix only the smells on the trigger's path. File the rest
   as tasks, one line each.
5. **Enforce every consolidation**, or it re-forks within a month:
   - an equality test between the paths that must agree
   - a "only this function builds X" or "never derive Y from Z" grep/AST test
   - each new check run once against the OLD code to prove it fails there
6. **Prove behaviour unchanged.** Capture an artefact BEFORE refactoring (the
   exact command line, output, or state the old code produces) and compare after.
   Then run the full suite. Any behaviour change is the operator's call.
7. **Write a short plan.** Sections: Context (why the change is big: the smells,
   a few bullets), Decisions (the operator's answers), Steps (refactors first,
   the trigger change last; each lands alone through the repo's gate), Tests (a
   table of check and the fault it catches), Not in this plan (task files),
   Verification. No file-by-file inventories. A long plan means the refactor is
   too big; cut it.
8. **Ask only behaviour questions** (deleting a mode users see, what appears on
   screen). Decide technical choices yourself and say what you chose.
9. **Execute step by step.** One worktree per step; run independent steps in
   parallel when their files do not overlap; land each through the repo's gate
   before building on it.

## Anti-patterns

- refactoring what is not on the trigger's path
- a "cleanup" that changes behaviour without a decision
- a consolidation with no check guarding it
- reading the whole repo before mapping the concept
- asking the operator to choose between technical options
- a plan longer than the change it enables
