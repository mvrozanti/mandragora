---
name: hotkeys
description: Use when adding, changing, looking up, or auditing keybindings/hotkeys/shortcuts across the mandragora repo. Loads the cross-program inventory and the user's existing binding "language" (modifier conventions, key families, shared prefixes) before proposing changes. Triggers on "bind X to Y", "what does <key> do", "find a free key for Z", conflict checks, hotkey audits, or any edit to hyprland/aerc/nvim/zsh/tmux/lf/mpv/waybar bindings.
---

# hotkeys — cross-program binding advisor

## Overview

The user's bindings span **8 dialects** (Hyprland, aerc, nvim, zsh, tmux, lf, mpv, waybar) with ~600 entries. They aren't 8 isolated configs — they're **one language** built up over years of muscle memory. Conventions repeat across tools. Treating them as a single namespace, with a normalized inventory, lets you spot conflicts, see free slots, and propose new bindings that fit instead of fighting the existing grammar.

This skill is the data layer (`bin/hotkey-index` produces a TSV) plus the methodology (this file).

## When to invoke

- "What does `<key>` do?" / "Is `<chord>` taken?"
- "Bind `<key>` to `<action>`" / "Add a hotkey for X"
- "Suggest a free key for Y"
- "Audit my hyprland binds" / "Find conflicts"
- About to edit any of: `.config/hypr/hyprland.conf`, `.config/aerc/binds.conf`, `.config/nvim/map.vim`, `.config/zsh/zshrc.zsh`, `.config/tmux/tmux.conf`, `.config/mpv/input.conf`, `modules/user/{lf,waybar,zx-dirs}.nix`.
- Refactoring a binding family (e.g. window-management cluster).

**Do NOT invoke when:**
- The user is editing a binding-adjacent line for an unrelated reason (whitespace, a command's args).
- The change is in a context with no binding semantics (e.g. waybar styling, hyprland decoration rules).

## Step 1 — always rebuild the index first

```bash
python3 /home/m/.claude/skills/hotkeys/bin/hotkey-index > /tmp/hotkeys.tsv
# (path is a symlink to agent-skills/hotkeys/bin/hotkey-index)
```

The index is **not committed/cached** — generate fresh every invocation. The repo changes constantly; a stale snapshot will mislead.

**TSV columns:** `scope | context | mods | key | action | file:line`

- `scope`: `hyprland | aerc | nvim | zsh | tmux | lf | mpv | waybar`
- `context`: submap (`global`, `gaps-all`, `powermenu`, `capture`), aerc section (`messages`, `view`, `compose`...), vim mode (`normal`, `insert`, `visual`...), tmux table (`prefix`, `root`, `copy-mode-vi`), zsh keymap (`emacs`, `viins`).
- `mods`: alphabetically sorted, `+`-joined: `SUPER`, `CTRL`, `SHIFT`, `ALT`, or combinations like `CTRL+SUPER`, `SHIFT+SUPER`.
- `key`: the key itself, normalized (e.g. `Q`, `j`, `F2`, `mouse:272`, `Tab`).
- `action`: the raw command, lightly whitespace-collapsed.
- `src`: `<file>:<line>` — always verify edge cases against the source.

## Step 2 — know the user's language

These conventions are observable in the inventory. Treat them as soft rules — propose changes that respect them and explicitly call out when you're departing.

### Layer-by-modifier

| Layer            | Modifier family          | Purpose                                                       |
|------------------|--------------------------|---------------------------------------------------------------|
| Desktop / WM     | `SUPER`, `SUPER+SHIFT`, `SUPER+CTRL` | Global Hyprland actions; never used inside terminal apps |
| Terminal apps    | `CTRL`, `ALT`            | nvim/tmux/aerc/zsh/lf — same chord = related action where possible |
| In-app modes     | (no modifier) single char | vim-style: `j`/`k`/`h`/`l`, `g`, `z`, etc.                    |
| Submap           | bare key inside submap   | Hyprland gaps-all, gaps-local, powermenu, capture             |

The hard rule: **`SUPER+_` is reserved for Hyprland**. Don't propose `SUPER+_` chords for inside-terminal actions — they'll never reach the app.

### Vim primitives are universal

`hjkl` means left/down/up/right *everywhere* — Hyprland focus, tmux pane, lf nav, vim, aerc message list. When proposing a movement-like action, default to hjkl. When proposing a non-movement action, **avoid** hjkl unless you're extending the family (e.g. `SHIFT+H/J/K/L` for "move thing in that direction").

### Capital is the louder cousin

Across most tools: lowercase = step / once, UPPER = bigger / file-level / stronger.

- Hyprland: `SUPER+J` focus down, `SUPER+SHIFT+J` move window down.
- aerc: `j`/`k` next/prev message, `J`/`K` next/prev folder.
- mpv: `j`/`k` cycle subs, `J`/`K` window-scale tweak; `w`/`b` seek 4s, `W`/`B` seek 16s.
- vim: many `<A-h>`/`<A-H>` resize-direction pairs.

When proposing a "stronger" variant of an existing lowercase binding, the capital is the natural slot.

### Family prefixes

- `z<letter>` — directory shortcut family. **Single source of truth: `modules/user/zx-dirs.nix`**. Consumed by both `lf` (as `g<letter>`) and `zsh` (as `z<letter>` shell aliases). Never add a `z<letter>` directly in `lf.nix` or `zshrc.zsh` — edit `zx-dirs.nix`.
- `o<letter>` — sort-order in lf (`os`/`oS`/`om`/`oM`/`oc`/`oC`).
- `p<letter>` — paste variants in lf (`pb`, `pB`).
- `y<letter>` — yank variants in lf (`P`/`N`/`B` for path/name/bytes).

When adding to a family, follow the existing micro-grammar (lowercase = ascending, uppercase = descending; etc.). Surface the family pattern to the user so they can intentionally extend it.

### Shared cross-tool conventions

- `Q` / `QQ` — quit (vim, hyprland-killactive, aerc).
- `Esc` — bail out / leave submap / cancel (Hyprland submaps, vim mode-exit).
- `<C-h>/<C-j>/<C-k>/<C-l>` — vim-aware cross-pane nav (vim ↔ tmux, see `is_vim` shell check in tmux.conf).
- `<A-h>/<A-j>/<A-k>/<A-l>` — same as above (alternate set).
- `Return` (`SUPER+Return`) — biggest-pane / "do the obvious thing".

### Submap semantics (Hyprland)

`SUPER+CTRL+G` enters `gaps-all`; `SUPER+SHIFT+G` enters `gaps-local`. Inside a submap, single keys do the work and `Esc`/`Return`/`Z`/`S`/`SHIFT+I` reset. When proposing a new "modal cluster" (e.g. a window-resize mode), the existing submap pattern is the template.

## Step 3 — querying the inventory

After generating `/tmp/hotkeys.tsv`, use these recipes. Pipe through `column -t -s$'\t'` for human-readable output.

```bash
# What's bound to a specific chord, anywhere?
awk -F'\t' '$3=="SUPER" && $4=="K"' /tmp/hotkeys.tsv

# Free-key check: which SUPER+letter slots are taken in Hyprland global?
awk -F'\t' '$1=="hyprland" && $2=="global" && $3=="SUPER" && length($4)==1 {print $4}' \
  /tmp/hotkeys.tsv | sort -u

# All bindings for a tool
awk -F'\t' '$1=="aerc"' /tmp/hotkeys.tsv | column -t -s$'\t'

# Cross-tool collisions on the same chord (informational — many are intentional;
# e.g. SUPER+J focus is Hyprland-layer while j next-message is aerc-layer)
awk -F'\t' '{print $3"|"$4}' /tmp/hotkeys.tsv | sort | uniq -c | sort -rn | head -20

# True conflicts: same scope+context, same chord, different actions
awk -F'\t' '{print $1"\t"$2"\t"$3"\t"$4}' /tmp/hotkeys.tsv | sort | uniq -d

# Family inspection: what's in the o-prefix family?
awk -F'\t' '$1=="lf" && $4 ~ /^o/' /tmp/hotkeys.tsv
```

**About "duplicates":** Hyprland intentionally chains multiple actions on one chord (e.g. `SUPER+Tab` = `cyclenext` AND `bringactivetotop`). Don't flag chained Hyprland binds as conflicts — they fire in sequence by design. Flag a true conflict only when the two actions are not part of an obvious pair.

## Step 4 — the advisory workflow

### When the user asks to BIND a new key

1. **Run `hotkey-index`**.
2. **Identify the layer**: desktop (Hyprland), terminal-global (zsh/tmux), or app-local (specific tool).
3. **Find the relevant family**: is this a movement? a launcher? a sort-order? a directory shortcut? Check the family-prefix list above.
4. **Check the slot**:
   - If a family fits, propose the next free slot in that family using its micro-grammar.
   - If no family fits, look for a free single chord in the relevant layer that the user will find memorable (mnemonic letter > arbitrary letter; lowercase > shifted).
5. **Check for collisions** in the same scope+context.
6. **Propose 1–3 options** with one-line reasoning each ("`SUPER+B` is free and B = browser fits the launcher pattern"). Always include a "doesn't fit because…" if you considered something and rejected it — the user makes better calls when they see the rejected options.
7. **Apply the edit** to the right file. Always patch the source — never the generated nix-store copy.
8. **Verify with `hyprctl configerrors`** if you touched Hyprland (per non-negotiable #11).

### When the user asks "what does X do?" / "is X taken?"

1. Run `hotkey-index`.
2. Show every match across scopes (a chord can be bound in multiple layers).
3. If the chord is unbound, say so explicitly and offer to bind it.

### When the user asks for an audit / "make this more intuitive"

1. Run `hotkey-index`.
2. Look for **inconsistencies**:
   - Lowercase/uppercase pair where only one half exists ("`SHIFT+H` doesn't have a sibling `H` doing the lighter action").
   - Same family with arbitrary letter assignments instead of mnemonic ones.
   - Identical actions bound to wildly different chords across tools (unify them).
   - Dead bindings (the action references a binary or function that no longer exists — verify with `which` / `command -v` / grep).
3. Look for **ergonomic issues**:
   - Capital chords without `SHIFT` typed as the modifier (e.g. `SHIFT+SUPER+P`) — flag if a lowercase slot is free and the action is frequent.
   - Three-modifier chords on common actions.
   - Chord that physically requires two hands but the action is paired with a one-handed predecessor.
4. **Present findings as a punch list** — small, independent, the user can pick which to apply. Don't bundle everything into a giant rewrite.

## Critical rules

1. **Single source of truth for `z<letter>`** — directory shortcuts go in `modules/user/zx-dirs.nix`. Never add `z<letter>` bindings directly to lf.nix or zshrc.zsh.
2. **Respect submap conventions** — Hyprland submaps use `Esc`, `Return`, `Z`, `S`, `SHIFT+I` to reset. New submaps must include those exits.
3. **No `SUPER+_` for in-app actions** — that chord never reaches the running terminal app.
4. **Hyprland sequential binds aren't conflicts** — `SUPER+Tab → cyclenext` and `SUPER+Tab → bringactivetotop` is intentional chaining.
5. **Vim/tmux navigation pair** — if you change `<C-h/j/k/l>` or `<A-h/j/k/l>` in either tmux.conf or map.vim, change the other to match. The `is_vim` shell predicate in tmux.conf depends on the pair.
6. **Edit source, not store** — the bindings live in `/etc/nixos/mandragora/`. The deployed `~/.config/...` paths are nix-store symlinks; editing them is a no-op and may be wiped at next switch.
7. **Hyprland validation** — after any hyprland.conf edit, `hyprctl configerrors` must be empty (per non-negotiable #11).
8. **Rebuild after committing** — bindings only become live after `mandragora-switch`. The user expects you to rebuild yourself; don't ask them to.

## Quick reference

| Need | Command |
|---|---|
| Generate inventory | `python3 ~/.claude/skills/hotkeys/bin/hotkey-index > /tmp/hotkeys.tsv` |
| Check a chord | `awk -F'\t' '$3=="SUPER" && $4=="K"' /tmp/hotkeys.tsv` |
| Free SUPER letters | `comm -23 <(printf '%s\n' {A..Z}) <(awk -F'\t' '$1=="hyprland" && $3=="SUPER" && length($4)==1' /tmp/hotkeys.tsv \| cut -f4 \| sort -u)` |
| All bindings for tool | `awk -F'\t' '$1=="aerc"' /tmp/hotkeys.tsv \| column -t -s$'\t'` |
| Family inspection | `awk -F'\t' '$4 ~ /^o/' /tmp/hotkeys.tsv` |
| Same-context dupes | `awk -F'\t' '{print $1"\t"$2"\t"$3"\t"$4}' /tmp/hotkeys.tsv \| sort \| uniq -d` |
| Validate hyprland | `hyprctl configerrors` |
| Rebuild | `mandragora-switch "<msg>"` |

## Hand-off

After the change, summarize:

```
Bound: <chord> -> <action>  (<scope>:<context>)
Fits convention: <family / pattern> | NEW family: <description>
Collisions checked: <none | listed>
Hyprland validation: <empty | errors and what you did>
Next: <mandragora-switch | already rebuilt>
```

Then stop. The user steers from there.
