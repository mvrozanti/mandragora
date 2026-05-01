# Multi-Agent File Safety

Concrete recovery from the multi-agent file-rewrite hazard
(AGENTS.md: "Never rewrite a file from scratch").

## The rule

Read the current on-disk state before any change, then patch only the
blocks relevant to your task. A full rewrite silently clobbers any
edits other agents have landed in the file since you last saw it —
the build still succeeds, so you may not notice for hours.

## If a full rewrite is unavoidable

1. Read the file first.
2. Preserve every section you are not explicitly replacing.
3. Write a handoff in `~/.ai-shared/handoffs/` describing the rewrite
   so other agents notice the churn. Protocol:
   `~/.ai-shared/rules/handoff.md`.

## Why the rule exists

On 2026-04-20 a full rewrite of `modules/user/home.nix` dropped the
`programs.firefox` block (with the Tridactyl native-messaging
wiring), making Firefox unlaunchable until the block was restored
from git. The rule is incident-driven, not theoretical.

## Quick integrity check

After heavy parallel-agent activity, eyeball line counts on
churn-prone files:

```bash
wc -l modules/user/home.nix
```

Historically, a drop below ~200 lines on `home.nix` means clobbered.
Restore with:

```bash
git checkout HEAD -- modules/user/home.nix
```
