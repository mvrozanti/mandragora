---
name: convince
description: Explicit-only (/convince). Write the shortest self-contained argument that justifies a claim, decision or recommendation to a reader who was not there — one paragraph of short, complete sentences in plain words, every one of them literally true, built around the single reason that carries the conclusion. Humane in tone, exact the way an engineer or a philosopher is exact; no jargon the reader would need explained, no persuasion tricks, no caveman fragments. Optional argument names the claim and/or the audience; with none, it argues the position currently on the table. Will not argue a claim that is false as stated — it says so and argues the true version instead.
---

# /convince — the short argument that holds

## What it is

One paragraph that makes a reader agree because they now see why, not
because they were pushed.

It is short, so a busy person reads all of it. It is self-contained, so it
works pasted anywhere. It is exact, so the sharpest person in the room finds
nothing false in it. The three pull against each other. The skill is
resolving that tension well.

## Invocation

- `/convince <claim>` — argue that claim.
- `/convince <claim> for <audience>` — "for my manager", "for a lawyer",
  "for someone who has never used Linux". The audience sets the vocabulary
  and what the argument leans on. It never changes what is true.
- `/convince` alone — argue the position currently on the table: the latest
  decision, recommendation or conclusion in this conversation. If two
  compete, take the most recent one the operator agreed with.
- **Default audience:** an intelligent outsider. Sharp, willing, busy, and
  holding none of this conversation's context.
- **Language:** the one the operator asked in, unless the audience implies
  another.

Exactly one reply. Ground the facts first if they need it — read the code,
check the number, look it up — read-only. Then the argument. Then normal
mode.

## Method

### 1. Check the claim before arguing it

An argument for something false is not worth writing well. Ask whether the
claim holds as stated.

- **True:** argue it.
- **True under a condition:** the condition goes inside the argument, once.
- **False or overstated:** say so in one line, then argue the strongest true
  version. Never manufacture support.

### 2. Find the load-bearing reason

The one fact that, once accepted, leaves the reader nowhere else to go. Most
claims have one. Five reasons means it has not been found yet. Three weak
reasons convince less than one strong one, because the reader attacks the
weakest and the rest fall with it.

A second reason earns a place only when the first cannot carry the
conclusion alone.

### 3. Pick the resolution

Describe things at the coarsest level at which every sentence is still true
and the conclusion still follows.

Coarser than that, something becomes false. Finer, and the reader carries
detail the conclusion never uses. When an objection lives one level down,
go down for that one sentence, or answer it in a clause.

### 4. Simplify by leaving out, never by bending

Anything may be omitted. Nothing kept may be distorted. A simplification is
legitimate when every inference a reasonable reader draws from it is still
true. "Usually", "in this case", "for the cases we test" are precision, not
hedging: use them exactly where they are the truth, and nowhere else.

### 5. Write it

The claim, the reason, and why the reason forces the claim. Add the
strongest objection, answered in one sentence, only if a sharp reader would
raise it unprompted. End on what follows: the consequence, the cost of the
alternative, or the decision.

## Voice

Humane, but the way an engineer or a philosopher talks. Plain words. Warm
enough. Never soft.

- **Short sentences, complete ones.** Subject, verb, articles. Most under
  fifteen words, none over twenty-five. Not caveman: "Config is code.
  Rollback easy." is a slogan, and slogans do not move anyone who thinks.
- **The connectives carry the logic.** "So", "because", "which means",
  "unless" are where the argument happens. Short sentences without them are
  a list of assertions.
- **Concrete over abstract.** A number or an example beats an adjective.
  "It took eleven hours" beats "it was slow".
- **Jargon only when the idea is needed and no plain word carries it** —
  and then say what it does in the same breath: "a cache, a nearby copy
  that is faster to reach".
- **One word per idea.** Do not vary terms for style; a reader assumes a new
  word names a new thing.
- **No persuasion tricks.** No urgency that is not real, no authority in
  place of a reason, no "obviously", no "simply", no rhetorical questions,
  no salesmanship. Needing a trick means the reason is not strong enough
  yet — back to step 2.
- **The engineer's habit:** name the mechanism, give the number, state the
  condition.
- **The philosopher's habit:** terms stay fixed, the inference is valid, and
  the strongest objection is met, not dodged.

## Length

One paragraph. Three to six sentences. Under 80 words by default, 120 at
most unless the operator asks for longer. No headers, bullets or bold inside
the argument — it is prose read top to bottom.

If the claim cannot be argued honestly in that space, say so and give the
shortest honest version. Never a compressed dishonest one.

## Output

```
[Not as stated: <what was wrong with the claim>]   only after step 1 corrected it

<the argument — one paragraph, ready to paste>

[Assumes: <premise taken as given>]                only if the reader might not grant it
```

Nothing else. No preamble, no "here is an argument", no offer to adjust.

## The check before sending

1. **Outsider.** Could a sharp stranger follow it holding only this
   paragraph? Every term is common or explained where it stands.
2. **Truth.** Is each sentence literally true as written, not true in
   spirit? Read it as the reader's most pedantic colleague would.
3. **Deletion.** Remove each sentence in turn. If the argument still stands
   without it, it was padding. Cut it.
4. **Validity.** Does the conclusion follow from what is on the page, or
   does it lean on something known but unsaid?
5. **Voice.** Any sentence over twenty-five words? Any fragment without a
   verb? Any word that pushes instead of shows?

## Examples

**Claim:** 0.999… equals 1. **Audience:** anyone.

Too technical:

> The decimal 0.999… denotes the limit of the partial sums of 9·10⁻ⁿ, which
> converges to 1 by the geometric series formula.

Caveman:

> No number between them. So same number. Done.

Convincing:

> The gap between 0.999… and 1 is smaller than 0.1. It is also smaller than
> 0.01, and 0.001, and any amount you care to name, however small, because
> there is always another nine. The only gap smaller than every amount is no
> gap at all. So they are one number, written two ways.

---

**Claim:** "NixOS means I can never break my system." **Audience:** a
developer who has never used Nix.

> Not as stated: it can still break. What NixOS gives is a cheap way back.
>
> On NixOS, the system's programs and settings are built from a description
> kept in files. Older builds stay until you delete them. So when a change
> breaks something, I pick the previous build as the machine starts, and its
> programs and settings are exactly what they were before. My own files are
> not touched by this. The only thing undone is the change.

---

**Claim:** write tests for the billing module before restructuring it.
**Audience:** a manager.

> Right now, nothing tells us if the billing code changes what it charges.
> If we restructure it as it is, the first sign of a mistake could be a
> wrong invoice. Tests written first record what it charges today, for the
> cases we pick. Then a mistake in those cases fails on our machines, before
> any customer sees it. That is about a day of work, against the cost of one
> wrong invoice.
>
> Assumes: the module has no tests today, and a day covers the main cases.

"For the cases we pick" is the precision. Without it the argument promises a
coverage that tests do not give, and the first engineer who reads it stops
trusting the rest.
