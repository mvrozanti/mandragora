# Repo Audits

Deterministic, errors-only test suite that enforces AGENTS.md
non-negotiables mechanically. Sibling to the runtime health checks in
`nix/modules/audits/{default,cve-scan}.nix` (disk, SMART, units, thermals,
strays) — those audit the *running system*; this audits the *repo*
before changes land.

Anti-goal: no LLMs in the audit loop. Shell + standard CLI tools plus
purpose-built linters (`statix`, `deadnix`, `shellcheck`, `hyprctl`);
no interpreter or model in the loop. If a check needs judgment, it doesn't belong here.

## Layout

```
.local/share/mandragora-audit/
  audit.sh              dispatcher
  lib/common.sh         OK/FAIL helpers, allowlist loader
  checks/NN-name.sh     one file per check, numbered for ordering
  allowlists/NAME.txt   exact whole-line entries; # for comments
  hooks/{pre-commit,commit-msg}
nix/modules/audits/repo.nix  packages mandragora-audit + sets core.hooksPath
```

## Invocation

- `mandragora-audit` — run everything against `/etc/nixos/mandragora`.
- `mandragora-audit --check NAME` — single check (with or without
  numeric prefix: `01-no-extraconfig` or `no-extraconfig`).
- `mandragora-audit --skip NAME` — drop a check (repeatable).
- `mandragora-audit --staged` — restrict scope to staged files
  (`git diff --cached --name-only`); used by the pre-commit hook.
- `mandragora-audit --list` — discovered checks.

Exit code: 0 = clean, 1 = at least one failure, 2 = bad invocation.

## Integration points

- **pre-commit hook** — runs all repo-tier checks on staged files,
  skips `conventional-commits` (commit message doesn't exist yet).
- **commit-msg hook** — runs `conventional-commits` against the
  candidate message file.
- **mandragora-switch** — runs the full audit before `git add -A`.
  A failure aborts the switch with no staging side-effects.

`core.hooksPath` is set declaratively by `system.activationScripts`
(see `nix/modules/audits/repo.nix`), pointing at the hooks dir inside
the audit's `/nix/store` derivation.

## Current checks

| # | Name | Rule | What it catches |
|---|------|------|-----------------|
| 01 | `no-extraconfig` | R2 | New `extraConfig = ''…''` blocks in `.nix` files. Allowlist: `allowlists/no-extraconfig.txt` (paths from repo root). |
| 02 | `doc-links`      | —  | Broken relative ``links`` links in tracked Markdown. |
| 03 | `conventional-commits` | R14 | Commit subjects not matching `<type>[(scope)][!]: <lowercase>`. |
| 04 | `hyprland-config` | R11 | Non-empty `hyprctl configerrors` when staged `.config/hypr/*.conf` changes; skips when hyprctl absent or no reachable instance. |
| 05 | `hub-tile` | R16 | A `https://<sub>.mvr.ac` caddy host under `nix/hosts/mandragora-vps/compose/` with no matching tile in `hub/static/index.html`. Allowlist: `allowlists/hub-tile.txt` (bare subdomains). |
| 06 | `no-projects-in-local-share` | R17 | Project markers (`.git`, `pyproject.toml`, `Cargo.toml`, `package.json`, `flake.nix`) under `.local/share/`. Allowlist: `allowlists/local-share-projects.txt` (top-level dir names). |
| 07 | `language-purity` | R2 | New inline `''…''` non-Nix heredocs (and `extraConfig = "…"`) in `.nix` files, excluding build phases, `writeShellScript*` wrappers, and prose-metadata attrs. Allowlist: `allowlists/language-purity.txt` (`path` or `path:line`). |
| 08 | `statix` | — | statix antipatterns in changed `.nix` files; skips unparseable files. Config in `statix.toml`. |
| 09 | `deadnix` | — | Dead code (unused `let` bindings / lambda args) in changed `.nix` files. |
| 10 | `shellcheck` | — | shellcheck findings (severity warning+) in changed shell scripts — `.sh` under `.local/bin/`, `.local/share/`, `nix/snippets/`, `docs/install/`, `agent-skills/`, plus extensionless executables with a bash/sh shebang; skips when shellcheck absent. Allowlist: `allowlists/shellcheck.txt` (paths from repo root). |

## Adding a check

1. Drop a script at `.local/share/mandragora-audit/checks/NN-name.sh`.
2. It receives `$AUDIT_HOME` and `$AUDIT_NAME` from the dispatcher.
   Source `lib/common.sh` for `audit_fail`, `audit_pass`,
   `audit_load_allowlist`, `audit_changed_files`.
3. Exit 0 = pass, 1 = fail. Print one `FAIL ...` line per violation
   with `file:line` citation.
4. If pre-existing violations exist, list them in
   `allowlists/<name>.txt` (one exact whole-line entry per line —
   a path, `path:line`, or bare name as the check matches; `#` for
   comments) and have the check load it via `audit_load_allowlist`.
5. Run `mandragora-switch` — the activation re-builds the audit tree
   and the new check participates immediately.

## Anti-patterns

- Magic in-code disable comments (`# audit-skip`) — violates R3.
  Use exact-match entries in `allowlists/`.
- Reading `secrets/` for validation — never. Use `sops` metadata
  if a secret-presence check is needed.
- Python or other interpreters in the loop — shell + standard CLI
  tools only; the sole compiled deps are the linters `statix`,
  `deadnix`, and `shellcheck` (and `hyprctl` on desktop hosts).
- LLM-based checks. The whole point is to stop trusting agent
  self-reports; layering an LLM under that defeats it.
