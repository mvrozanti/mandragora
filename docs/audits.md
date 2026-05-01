# Repo Audits

Deterministic, errors-only test suite that enforces AGENTS.md
non-negotiables mechanically. Sibling to the runtime health checks in
`modules/audits/{default,cve-scan}.nix` (disk, SMART, units, thermals,
strays) — those audit the *running system*; this audits the *repo*
before changes land.

Anti-goal: no LLMs in the audit loop. Pure shell + ripgrep. If a check
needs judgment, it doesn't belong here.

## Layout

```
.local/share/mandragora-audit/
  audit.sh              dispatcher
  lib/common.sh         OK/FAIL helpers, allowlist loader
  checks/NN-name.sh     one file per check, numbered for ordering
  allowlists/NAME.txt   path-globs per line; # for comments
  hooks/{pre-commit,commit-msg}
modules/audits/repo.nix  packages mandragora-audit + sets core.hooksPath
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
(see `modules/audits/repo.nix`), pointing at the hooks dir inside
the audit's `/nix/store` derivation.

## Current checks

| # | Name | Rule | What it catches |
|---|------|------|-----------------|
| 01 | `no-extraconfig` | R2 | New `extraConfig = ''…''` blocks in `.nix` files. |
| 02 | `doc-links`      | —  | Broken relative `[text](path)` links in tracked Markdown. |
| 03 | `conventional-commits` | R14 | Commit subjects not matching `<type>[(scope)][!]: <lowercase>`. |

## Adding a check

1. Drop a script at `.local/share/mandragora-audit/checks/NN-name.sh`.
2. It receives `$AUDIT_HOME` and `$AUDIT_NAME` from the dispatcher.
   Source `lib/common.sh` for `audit_fail`, `audit_pass`,
   `audit_load_allowlist`, `audit_changed_files`.
3. Exit 0 = pass, 1 = fail. Print one `FAIL ...` line per violation
   with `file:line` citation.
4. If pre-existing violations exist, list them in
   `allowlists/<name>.txt` (one path per line, `#` for comments)
   and have the check load it.
5. Run `mandragora-switch` — the activation re-builds the audit tree
   and the new check participates immediately.

## Anti-patterns

- Magic in-code disable comments (`# audit-skip`) — violates R3.
  Use path-globs in `allowlists/`.
- Reading `secrets/` for validation — never. Use `sops` metadata
  if a secret-presence check is needed.
- Python or other build deps — pure shell + standard CLI tools.
- LLM-based checks. The whole point is to stop trusting agent
  self-reports; layering an LLM under that defeats it.
