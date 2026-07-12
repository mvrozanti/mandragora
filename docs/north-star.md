# North Star — Surviving Improvement Roadmap

Directional backlog. Not a sprint plan — a ranked pool of verified,
concrete improvements. Each item names the evidence so future sessions
can act without re-auditing.

Origin: a full-repo audit (2026-07) enumerated 30 concrete improvements.
A batch shipped 2026-07-12 closed nearly all of them; what remains below
are the items still open — a few shipped-with-a-known-remainder, the rest
untouched. Each survivor names the evidence so future sessions can act
without re-auditing.

Protocol: when an item ships, delete it from this file in the same
commit (the diff is the changelog). When an item is rejected, delete it
and note why in the commit body. Keep the list honest; a North Star
document that accumulates stale entries becomes noise.

Items are grouped by theme and roughly ordered by leverage within each
group.

## Guardrails

1. **Burn down the language-purity allowlist.**
   `.local/share/mandragora-audit/allowlists/language-purity.txt` still
   grandfathers a handful of inline-heredoc violations of Rule 2
   (`flake.nix`, `nix/modules/core/secrets.nix` ×2,
   `nix/modules/user/{rss-menu,security-menu,terminal}.nix`,
   `nix/pkgs/refiner/default.nix` — currently 7 entries). Convert them
   to `builtins.readFile` snippets a few per session until the allowlist
   is empty; each conversion also makes the config testable outside Nix.

## Dead weight

2. **Retire the legacy `mbsync-notify` launcher.**
   `.local/bin/mbsync-notify.sh` is still built into a
   `writeShellScriptBin` by `nix/modules/user/home.nix` (line 362) and
   still carried in the `mandragora-pkg-diff` filter list
   (`.local/bin/mandragora-pkg-diff.sh:119`). Drop that wrapper and its
   filter entry, then delete the script.

## Operations and resilience

3. **Extend the backup tiers to photos/bulk.**
   The resilient tier ships: `nix/modules/core/backup.nix` runs a daily
   restic backup of `/persistent/home/m/Documents` to the VPS plus a
   weekly `restic-lifeboat` job that verifies age-key validity and repo
   integrity. What is not yet covered is the photos/bulk tier —
   `~/Pictures` and the larger user-data ranks in
   [`persistence.md`](persistence.md) — which is blocked on a real
   target: the VPS repo host has ~27 GB free against a ~29 GB `Pictures`
   set. Pick a destination (bigger VPS volume, off-site object store, or
   local cold disk) and wire the remaining tiers to the same restic
   pattern.

4. **Migrate `rgb-control` state off the live repo path.**
   The service code now loads from the store — every `ExecStart` points
   at a store path, no running unit executes from
   `/persistent/mandragora/...`. The one residual writer is
   `rgb-control`: `.local/share/rgb-control/rgb-control.py` (lines 55–56)
   still hardcodes `STATE_DIR = /persistent/mandragora/.local/share/rgb-control`
   and writes `state.json` there. Point it at an XDG state dir (or
   `/persistent/rgb-control/`) so a mid-rebase repo or worktree checkout
   can't shift where runtime state lands.
