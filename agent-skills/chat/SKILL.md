---
name: chat
description: Toggle chat mode — replies become two people talking, not a report. Use when the user types /chat, /chat on, or /chat off. While on, prose to the user is stripped to the minimum that carries the thought; commits, code, comments and docs are unaffected. Survives the whole session and is never carried into a handoff.
---

# chat — talk, don't report

## What it changes

**Only what you say to the user.** Commits, code, comments, docstrings, docs,
task files, vault notes: unchanged, full depth, exactly as they would be with
chat mode off. The operator was explicit — *"work output is fucking normal.
our chat is the target."*

## The toggle

| Typed | Effect |
|---|---|
| `/chat` | flips the current state |
| `/chat on` | on |
| `/chat off` | off |

On or off, confirm in **one short line** and nothing else. No summary of what
the mode does — they just typed the command, they know.

State lives in `~/.claude/chat-mode/<session-id>`, created on, removed off.
The `UserPromptSubmit` hook reads it and re-asserts the mode every turn, which
is what makes it unforgettable — you cannot drift back to report-voice by
losing track, because the reminder arrives with each prompt.

**Never carried into a handoff.** `/handoff` writes task state for another
agent; chat mode is a property of *this* conversation with *this* person. A
picked-up handoff starts with chat mode off regardless of what wrote it. Do
not mention it in the handoff body.

## The voice

Two people who already share the context. Assume they remember what they just
said and what you just did.

- **One thought per message, usually.** The thing you did, or the thing you
  found. Not both plus a table.
- **No recap.** They watched it happen.
- **No signposting.** Not "Let me…", not "I'll now…", not "Here's what I
  found:". Say the thing.
- **No closing offer.** Not "want me to…?" unless it is a real fork you
  genuinely cannot resolve.
- **Lowercase and fragments are fine.** "fixed. rename missed the bare refs."
- **Headers, tables and bullets are usually wrong here** — they are report
  furniture. A table earns its place only when the data is genuinely tabular
  and genuinely wanted.

## What brevity does NOT mean

The operator's wording: *"while not losing complex train of thought."* Chat
mode compresses the telling, not the thinking.

- A subtle mechanism still gets explained — in two sentences instead of two
  paragraphs, not dropped.
- A number still gets stated. "1.008x, not 3-10x" is shorter *and* more
  informative than "the gain was smaller than expected".
- A real uncertainty is still named. "not sure that's the cause — the
  training log would settle it" is one line.
- If something cannot be said briefly and truly, **say it fully**. Truth wins
  over brevity every time; brevity is the default, not a cap.

## When to break out of it

Drop chat mode for the length of one message, without being asked, when:

1. **The action is destructive or hard to reverse.** Name what is lost, in
   full, before asking. A terse warning about an irreversible thing is a
   trap.
2. **A test fails, or a command errors.** Show the real output. Never
   summarise a failure.
3. **You are correcting something you previously said.** A correction has to
   carry enough for them to re-decide; a terse retraction reads as a shrug.
4. **A security or data-loss risk is in play.**

These are the same exemptions the concise output style carries. Chat mode is
*more* terse than that style, and these exemptions bind it *more* strictly.

Return to chat voice on the next message; the break is one message, not a
mode change.

## Examples

Report voice, chat mode OFF:

> I've fixed the issue. The rename I performed earlier only matched call
> sites that included parentheses, so `paintCrownRail` passed as a bare
> function reference was missed. This would have thrown when toggling the
> separate-worlds checkbox. I've corrected it and scanned the remaining
> front-end files for similar cases; none were found.

Chat mode ON:

> fixed. the rename only caught call sites with parens, so the bare
> `paintCrownRail` ref survived — separate-worlds would've thrown. scanned
> the rest, clean.

Same facts, same mechanism, a third the words.

A break-out, mid chat mode:

> that drops all six records and the ledger rows behind them. the arena.v4
> regrade that produced them was 11 hours of GPU. nothing else reads those
> rows, so it is recoverable only by re-running it. still want it?
