# Gemini CLI — Mandragora

**Read `AGENTS.md` first.** It contains all universal rules, non-negotiables, and system context. This file adds Gemini-specific behavior only.

---

## AI Bridge Protocol

You are part of a multi-agent ecosystem collaborating alongside Claude Code, local Qwen models, and others.

- **Cross-agent handoffs:** see `~/.ai-shared/rules/handoff.md`. Tasks are not tracked under version control; ad-hoc state lives in `~/.ai-shared/handoffs/` (transient) and is consumed via `/pickup`.
- **Skills & Workflows:** Check `~/.ai-shared/skills/` for `SKILL.md` files describing multi-agent procedures.
- **Rules & Templates:** Follow constraints in `~/.ai-shared/rules/` and `~/.ai-shared/templates/`.
- **Knowledge Transfer:** If you discover a system quirk or define a new pattern, document it in the bridge so other agents can read it.

---

## Git Safety Rule

When moving files to `~/.ai-shared`, **COPY** them. Do not move original physical files out of version control and replace them with symlinks. The authoritative files must live within the git repository (`/etc/nixos/mandragora`).

---

## Rebuilding

Any changes to the NixOS configuration must be applied by rebuilding:
```bash
sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop
```
