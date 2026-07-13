# North Star — Surviving Improvement Roadmap

Directional backlog. Not a sprint plan — a ranked pool of verified,
concrete improvements. Each item names the evidence so future sessions
can act without re-auditing.

Origin: a full-repo audit (2026-07) enumerated 30 concrete improvements.
A batch shipped 2026-07-12 closed nearly all of them; what remains below
is the single item still open. It names the evidence so future sessions
can act without re-auditing.

Protocol: when an item ships, delete it from this file in the same
commit (the diff is the changelog). When an item is rejected, delete it
and note why in the commit body. Keep the list honest; a North Star
document that accumulates stale entries becomes noise.

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
