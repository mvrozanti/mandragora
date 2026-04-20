# AGENTS.md — Mandragora Routing Table

AI context budget is finite. Read only what your task requires. This file routes you.

---

## Always Read First (Every Session)

```
atlas/non-negotiables.md   ← hard constraints; violations are unacceptable
DECISIONS.md               ← all resolved technical choices
atlas/hardware.md          ← physical DNA; all proposals must fit this hardware
```

---

## Routing Table

| Task | Read These | Skip These |
|------|-----------|------------|
| Proposing any Nix change | `DECISIONS.md`, `atlas/non-negotiables.md`, `STRUCTURE.md` | `SITUATIONS.md`, `atlas/ideation.md` |
| Adding a package / module | `DECISIONS.md`, `STRUCTURE.md`, `atlas/software.md` | `EXECUTION_PLAN.md`, `SHADOW.md` |
| Hardware-specific config (GPU, RGB, cooling) | `DECISIONS.md`, `atlas/hardware.md`, `atlas/software.md` | `DATA_HIERARCHY.md`, `WORKFLOW.md` |
| Storage / persistence / backup | `DECISIONS.md`, `atlas/PARTITION_PLAN.md` | `SHADOW.md`, `atlas/ideation.md` |
| Secrets / credentials / sops | `DECISIONS.md`, `SECRETS.md`, `atlas/non-negotiables.md` | Everything else |
| Build phases / what to do next | `EXECUTION_PLAN.md`, `atlas/TODO.md` | `SHADOW.md`, `SECRETS.md` |
| Sync, Git, Seafile workflow | `WORKFLOW.md`, `DATA_HIERARCHY.md` | `SHADOW.md`, `atlas/ideation.md` |
| Ricing / theming / aesthetics | `DECISIONS.md`, `atlas/software.md`, `SITUATIONS.md` | `SECRETS.md`, `DATA_HIERARCHY.md` |
| "Why does X work this way?" | `SITUATIONS.md`, `DECISIONS.md` | `SHADOW.md`, `atlas/ideation.md` |
| Horizon / wishlist / future ideas | `atlas/ideation.md`, `atlas/inspiration.md`, `atlas/PRD.md` | `SECRETS.md`, `EXECUTION_PLAN.md` |
| Full system orientation (new session) | `README.md`, `DECISIONS.md`, `STRUCTURE.md` | `SHADOW.md`, `SECRETS.md` |

---

## File Index

```
README.md                  Front door: Mermaid diagrams, hardware summary, quick reference
DECISIONS.md               ALL resolved technical choices — read this first
STRUCTURE.md               Directory layout and Language Purity rule (Nix-only logic)
WORKFLOW.md                Sync ritual: Flake=Git, Seafile=user data, "Tailor" alias
DATA_HIERARCHY.md          5-tier persistence/backup matrix (what survives what)
EXECUTION_PLAN.md          Build checklist with phase checkboxes
SITUATIONS.md              Tactical day-to-day decisions (packages, wifi, Hyprland, etc.)
SHADOW.md                  Shadow profile architecture  ← see rules below
SECRETS.md                 sops-nix vault strategy      ← see rules below

atlas/PARTITION_PLAN.md    Disk layout, Btrfs subvolumes, boot config details
atlas/hardware.md          Full hardware specs and assembly rituals
atlas/software.md          Drivers, RGB, fan control, monitoring, Ryzen tuning
atlas/non-negotiables.md   Hard constraints — read before proposing ANYTHING
atlas/ideation.md          Evolving wishlist: impermanence, dashboards, soundscapes
atlas/TODO.md              Current execution roadmap with phase checkboxes
atlas/PRD.md               Vision, profiles, non-negotiables summary, roadmap (reference)

appendix/                  Self-contained subprojects; ignore unless explicitly asked
```

---

## Hard Rules

**No Comments:** Never include comments in any code, script, or Nix expression. The logic must be self-documenting through clean naming and structure. Existing comments must be purged.

**Shadow:** Zero visibility by default. Do not read `SHADOW.md` or reason about the Shadow profile unless the user explicitly asks. In standard operation, Shadow does not exist.

**Secrets:** Never print, log, or repeat anything from `secrets/` or `SECRETS.md`. Treat the `secrets/` directory as opaque.

**Declarative supremacy:** Never propose an imperative command (`chmod`, `systemctl`, `pacman -S` on the main system) as a solution. All changes are Nix expressions.

**File isolation:** Non-Nix logic (shell, Python, Lua, CSS) lives in XDG-mirrored directories at the repo root (`.local/bin/`, `.config/<app>/`, `etc/`) and is referenced from Nix via `builtins.readFile`. The `snippets/` directory no longer exists — it was removed 2026-04-20.

**Persistence check:** Any change touching `/home` must be reconciled with `DECISIONS.md` before proposing.

---

## Communication Contract

- No apologies, no filler — technical rationale only.
- Propose a reproduction step before calling anything "fixed."
- When ricing: cite the current value, propose the new value, explain why.
- **Language Purity:** NEVER embed non-Nix code (shell, Lua, CSS, Python, etc.) inside `.nix` files via `extraConfig`, `postShellInit`, or similar string blocks. All external logic MUST be moved to `snippets/` and referenced from Nix using the `builtins.readFile` or `pkgs.substituteAll` patterns. This is non-negotiable and absolute.
- **Output Language:** Always respond in English regardless of user's input language. Do not translate code blocks, CLI commands, file paths, logs, or technical artifacts.
