# CLAUDE.md — Mandragora NixOS (Claude Code Addendum)

**Read [`AGENTS.md`](./AGENTS.md) first.** It is the canonical source for
hard constraints, the impermanence rule, the multi-agent safety rule, the
Edit → Rebuild → Verify workflow, the AI bridge, and the key-files quick
reference. This file holds only the Claude-specific delta.

---

## File Permissions & Sudo Context

- `/etc/nixos/mandragora/` is owned by `m:users` — Claude Code can edit
  files directly.
- `nixos-rebuild switch` requires `sudo` — Claude Code cannot run this; tell
  the user, or instruct them to type `! sudo <command>` (the `!` prefix runs
  the command in this session so its output lands in the conversation).

---

## Repository Path Note

`/etc/nixos/mandragora/` is bind-mounted from `/persistent/mandragora/`.
Both paths point at the same files; either works for reads and edits. The
parent `/etc/` is wiped on boot, but the bind-mount restores
`/etc/nixos/mandragora` to its persistent contents on every boot, so the
working tree itself survives. The git remote is the persistence mechanism
for the *source of truth* (and against accidental wipes of the persistent
subvolume); commit and push before rebooting as a safety habit.

---

## Memory System

User preferences and project state persist across conversations at:

```
~/.claude/projects/-home-m/memory/
```

Index: `~/.claude/projects/-home-m/memory/MEMORY.md`

Update memories when you learn something important about the user or system
that would help future sessions. Always check for stale memories before
acting on them.

---

## SSH Key Import Process

When the user is ready to import SSH keys into sops:

```bash
sops /etc/nixos/mandragora/secrets/secrets.yaml
# Add under 'ssh:' key:
#    id_ed25519: |
#      -----BEGIN OPENSSH PRIVATE KEY-----
#      ...
#      -----END OPENSSH PRIVATE KEY-----

# In modules/core/secrets.nix, add to sops.secrets:
#    "ssh/id_ed25519"     = { path = "/home/m/.ssh/id_ed25519";     owner = "m"; mode = "0600"; };
#    "ssh/id_ed25519.pub" = { path = "/home/m/.ssh/id_ed25519.pub"; owner = "m"; mode = "0644"; };

# Rebuild
mandragora-switch "import ssh keys via sops"
```

The age decryption key is at `/persistent/secrets/keys.txt` (root-only,
survives reboots).

---

## Old Reference Repo

The user's previous Arch + bspwm configuration lives at:

- Local clone: `~/projects/mandragora`
- GitHub: `https://github.com/mvrozanti/mandragora`

When migrating configs (zsh, tmux, neovim, etc.), fetch from there. Always
translate to Nix — do not copy imperative configs verbatim.
