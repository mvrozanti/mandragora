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
   grandfathers 5 inline blocks: `flake.nix:80`
   (`systemBuilderCommands` writing `$out/git-revision`),
   `nix/modules/core/secrets.nix:98`+`:105` (sops template `content`
   with `${config.sops.placeholder…}` interpolation, resolved at
   activation), `nix/modules/user/terminal.nix:158` (kitty
   `extraConfig` one-line `include`), and `nix/pkgs/refiner/default.nix:26`
   (`writeShellApplication` body templating `${usbImage}`/`${ovmf}`/
   `${scripts}` store paths). Each survivor either carries Nix
   interpolation that a static `builtins.readFile` snippet cannot
   reproduce byte-for-byte, or is the sanctioned `writeShellApplication`
   mechanism itself — so the plain extract-to-snippet route no longer
   applies. Any further reduction needs a different tactic (e.g. a
   template file plus `substituteAll`), only worth it if it stays
   byte-identical.

## Operations and resilience

2. **Extend the backup tiers to photos/bulk.**
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
