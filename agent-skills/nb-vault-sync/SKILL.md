---
name: nb-vault-sync
description: Use when the user wants to refresh Open Notebook (nb.mvr.ac) with the current state of the mandragora-desktop obsidian vault. Runs the `nb-vault-sync` CLI, which idempotently diffs `~/Documents/mandragora-desktop-obsidian-vault/` against the `vault` notebook in Open Notebook and POST/DELETEs sources to match. Manual trigger only — never auto-run on edits, never embed (LLM cost) unless the user asks. Trigger phrases: "sync vault to nb", "refresh open-notebook", "update notebook from vault", "/nb-sync".
---

# nb-vault-sync — push vault → Open Notebook

## Overview

`~/Documents/mandragora-desktop-obsidian-vault/` is the source of truth (also served as the graph at demo.mvr.ac). Open Notebook (nb.mvr.ac) holds a one-way mirror in a single notebook named `vault`. This skill triggers the mirror refresh.

**Direction is strictly one-way:** vault → nb. Notes created inside Open Notebook are NOT written back.

**Manual only:** there is intentionally no inotify watcher, no timer, no hook. The user runs the skill (or the binary) when they want the mirror to catch up.

## When to invoke

- "sync vault to nb", "push vault into open notebook", "refresh nb sources", "update notebook from vault", `/nb-sync`.
- After a notable batch of vault edits the user wants reflected in nb.
- The user mentions Open Notebook is stale / missing recent notes.

**Do NOT invoke when:**
- The user is editing a single note and hasn't asked. The skill is for batched, explicit refreshes.
- Open Notebook is unreachable (tailnet down). Surface the error, do not retry blindly.

## How it works

The CLI is provided by `nix/modules/user/nb-vault-sync.nix` (built from `nix/snippets/nb-vault-sync.py`) and lands on `$PATH` as `nb-vault-sync`.

It:
1. Walks the vault, collecting every `*.md` (skips dotfiles / dotdirs — `.obsidian/`, `.git/`, etc.).
2. SHA-256s each file.
3. Reads `~/.local/state/nb-vault-sync/state.json` (`{relpath: {source_id, sha256}}`).
4. For each file:
   - hash unchanged → skip.
   - hash changed → DELETE old source, POST new (`SourceUpdate` only supports title/topics — content changes must replace).
   - new file → POST new source under the `vault` notebook.
5. For each tracked relpath no longer in the vault → DELETE the source.
6. Writes state back.

API endpoint defaults to `http://100.84.78.83:5055` — port 5055 is bound to the VPS tailnet IP only (see `nix/hosts/mandragora-vps/compose/nb/docker-compose.yml`), so no Authelia friction. The public 8502 → `nb.mvr.ac` path stays Authelia-gated.

## Flags

```
nb-vault-sync                # real sync, no embeddings
nb-vault-sync --dry-run      # print + / ~ / - decisions, hit no endpoints (notebook id "DRY")
nb-vault-sync --embed        # also vector-embed (costs LLM tokens; rare — only when user asks)
nb-vault-sync --vault PATH   # override default vault dir
nb-vault-sync --api URL      # override default API base
nb-vault-sync --notebook NAME  # override notebook name (default `vault`)
```

Env overrides: `NB_VAULT_DIR`, `NB_API_URL`, `NB_NOTEBOOK`, `NB_STATE`.

## Procedure

1. **Always dry-run first** when the diff might be large or the user just edited many files:
   ```bash
   nb-vault-sync --dry-run
   ```
   Eyeball the `created`/`updated`/`deleted` totals. If any of those numbers look implausible (e.g. `deleted=823` after a path move), STOP and surface to the user — don't blow away the mirror.
2. Real sync:
   ```bash
   nb-vault-sync
   ```
3. Report the summary line (`done: created=… updated=… deleted=… unchanged=…`) verbatim.

## Insight regeneration

Open Notebook can re-generate per-source insights, but this is gated behind explicit user request — it spends LLM tokens per source. Do not pass `--embed` and do not call `POST /api/sources/{id}/insights` from this skill unless the user explicitly asks for embeddings or insights.

## Failure handling

- Connection refused → tailnet to VPS is down. Check `ping 100.84.78.83` and `curl -s http://100.84.78.83:5055/api/notebooks`. Surface the error; do not retry.
- 422 from `/api/sources/json` → schema drift in upstream `lfnovo/open-notebook`. Compare against `nix/snippets/nb-vault-sync.py:create_source` and patch the payload — `SourceCreate` schema is in the live `/openapi.json`.
- State file diverges from server state (e.g. someone deleted sources via the UI) → safe to delete `~/.local/state/nb-vault-sync/state.json` and re-run; the script will rebuild it (this re-POSTs every file once).

## Where things live

- CLI source: `/etc/nixos/mandragora/nix/snippets/nb-vault-sync.py`
- CLI Nix wrapper: `/etc/nixos/mandragora/nix/modules/user/nb-vault-sync.nix`
- Stack: `/etc/nixos/mandragora/nix/hosts/mandragora-vps/compose/nb/`
- State: `~/.local/state/nb-vault-sync/state.json`
- Vault: `~/Documents/mandragora-desktop-obsidian-vault/`
