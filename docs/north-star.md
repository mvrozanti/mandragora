# North Star — 30-Item Improvement Roadmap

Directional backlog produced by a full-repo audit (2026-07). Not a
sprint plan — a ranked pool of verified, concrete improvements. Each
item names the evidence so future sessions can act without re-auditing.

Protocol: when an item ships, delete it from this file in the same
commit (the diff is the changelog). When an item is rejected, delete it
and note why in the commit body. Keep the list honest; a North Star
document that accumulates stale entries becomes noise.

Items are grouped by theme and roughly ordered by leverage within each
group. Cross-group priority: fix the latent bugs first — they are
already wrong today; everything else is drift.

## Latent bugs

1. **Define `QuotaExceeded` in the watch judge.**
   `nix/hosts/mandragora-vps/compose/watch/app/main.py:508` and
   `telegram.py:343` catch `judge.QuotaExceeded`, but `judge.py`
   defines no such class — the except clause itself raises
   `AttributeError` the moment a quota error occurs, so the graceful
   degradation path has never worked. Define the exception (or catch
   the real one the judge raises).

2. **Make release-source bootstrap honor feed-only push.**
   `watch/app/release-sources.txt` documents that bootstrapped
   `github_release` watchers are feed-only (`push=0`), but
   `bootstrap_release_sources()` in `main.py` INSERTs with a hardcoded
   `push=1`. Every curated release source pushes to Telegram against
   the layer's design intent. One-character fix plus a migration for
   already-bootstrapped rows.

3. **Fix the waybar path in `hotkey-index`.**
   `agent-skills/hotkeys/bin/hotkey-index:324` reads
   `REPO / "modules/user/waybar.nix"`; the real path is
   `nix/modules/user/waybar.nix`. `parse_waybar()` silently finds
   nothing, so waybar bindings are absent from every hotkey audit.

4. **Wire `hyprlandConfigGuard` into flake checks — or delete it.**
   `nix/modules/shared/build-checks.nix` defines and exports four
   guards; `flake.nix:146-148` wires only `closureSizeGuard`,
   `profileEvalGuard`, `sopsKeyGuard`. `hyprlandConfigGuard` is dead
   weight that looks like coverage.

5. **Restore `docs/install/format-drive.sh`.**
   [`install/INSTALL.md`](install/INSTALL.md) (steps at lines 18 and
   58) and [`architecture.md`](architecture.md) both invoke it; the
   file does not exist. The fresh-install runbook — the artifact that
   backs the "reproducible in < 30 min" invariant — is broken at the
   partitioning step. Write the script from the subvolume layout the
   INSTALL.md table already documents.

## Documentation accuracy

6. **Refresh [`architecture.md`](architecture.md).**
   It claims "single host" (line 3) while the flake ships four
   (desktop, wsl, usb, vps), and "There is no test suite" (line 287)
   while `mandragora-audit` runs twelve checks and the USB installer has
   five bats suites. The module inventory predates several directories.
   This is the first doc an agent loads for structure; wrong claims
   here propagate.

7. **Document all nine audit checks in [`audits.md`](audits.md).**
   The "Current checks" table stops at 03. Missing: 04-hyprland-config,
   05-hub-tile, 06-no-projects-in-local-share, 07-language-purity,
   08-statix, 09-deadnix — including where their allowlists live.

8. **Fix [`secrets.md`](secrets.md) section numbering.**
   Headings run 1, 3, 4, 6 — sections 2 and 5 are missing. Either
   content was lost in an edit (recover it) or the numbering is stale
   (renumber).

9. **Refresh the VPS `INVENTORY.md`.**
   `nix/hosts/mandragora-vps/INVENTORY.md` has drifted from the ~30
   live compose stacks. It is the router for VPS work; an inventory
   that omits stacks makes agents rediscover them by `ls` every
   session.

10. **Expand the top-level `README.md`.**
    24 lines for a repo this size. Add the host matrix, a pointer to
    [`index.md`](index.md), the audit/rebuild workflow in three lines,
    and a screenshot. GitHub is the only surface where this repo has
    no docs.

## Guardrails

11. **Add a shellcheck audit check.**
    `.local/bin/` and `nix/snippets/*.sh` carry dozens of shell
    scripts with no lint gate. Add check `10-shellcheck` following the
    existing allowlist pattern for grandfathered warnings.

12. **Run the bats suites from `nix flake check`.**
    `nix/hosts/mandragora-usb/tests/install/` holds five bats suites
    that only run when someone remembers the refiner harness. Wrap
    them in a `runCommand` check so `nix flake check` executes them.

13. **Adopt a Nix formatter.**
    No `formatter` output in the flake, no format gate in the audit.
    Pick `nixfmt-rfc-style` (or alejandra), format the tree once, add
    check `12-nixfmt`. Ends per-agent style drift at the source.

14. **Burn down the language-purity allowlist.**
    `.local/share/mandragora-audit/allowlists/language-purity.txt`
    grandfathers 24 inline-heredoc violations of Rule 2. Convert them
    to `builtins.readFile` snippets a few per session until the
    allowlist is empty; each conversion also makes the config testable
    outside Nix.

15. **Burn down the no-extraconfig allowlist.**
    Same pattern, check 01: `tmux.nix` and `home.nix` entries remain.
    Finishing this closes the oldest grandfather clause in the repo.

## Consolidation

16. **Split `nix/modules/user/home.nix`.**
    986 lines — the largest module in the tree and the default
    merge-conflict arena for parallel agents. Extract topical modules
    (packages, xdg, activation scripts, misc programs) so each is one
    screen and one concern.

17. **Split `nix/modules/core/monitoring.nix`.**
    20K in one module covering exporters, dashboards, and alerting.
    Same treatment as home.nix.

18. **Centralize tailnet IPs and ports.**
    `100.115.80.79` (desktop) and `100.84.78.83` (vps) are hardcoded
    across compose files, socat unit templates, and nix modules. One
    attrset in a shared module, consumed by both the nix tree and the
    compose generator, makes a future IP change a one-line diff
    instead of a repo-wide grep.

19. **Centralize model tags.**
    Ollama model names repeat across `thought/config.py`,
    `llm-via-telegram`, `crush.json`, and several modules —
    [`model-migration.md`](model-migration.md) exists precisely because
    the scatter makes migration a checklist. Fix the scatter and the
    checklist shrinks to one edit.

20. **Template the eight identical VPS proxy stacks.**
    `stt`, `tts`, `kl`, `music`, `vtag`, `semantic`, `axon`, `cv-es`
    under `nix/hosts/mandragora-vps/compose/` are the same
    caddy-label + socat-forward compose file differing only in
    hostname and port. Generate them from one function over an
    attrset; adding subdomain number nine becomes one line.

21. **Unify VPS deployment.**
    Each stack deploys by ad-hoc rsync from the desktop. One driver
    script (manifest of stacks → rsync → `docker compose up -d`
    remotely) or a git-pull-on-VPS flow gives idempotent redeploys and
    an audit trail of what is live.

22. **Deduplicate shell aliases.**
    `nix/snippets/aliases.zsh` defines `gcd` twice with different
    meanings (`git diff` at line 195, greatest-common-divisor at line
    343 — the second silently wins) and `rh` twice (lines 358, 384);
    more collide across `zshrc.zsh` and `zsh.nix`. Dedupe and pick one
    home per alias.

24. **Deduplicate keyledsd snippets.**
    `nix/snippets/lightning.lua` and
    `nix/snippets/keyledsd-effects/lightning.lua` are parallel copies.
    Keep the `keyledsd-effects/` one, fix references, delete the
    stray. Sweep the remaining `keyledsd-effects/` files for the same
    pattern while there.

## Dead weight

25. **Retire the legacy `mbsync-notify` launcher.**
    The committed runtime artifacts are gone — the
    `keyleds-host-mode` bytecode, the tracked
    `.local/share/rgb-control/state.json`, and the pre-rewrite
    `compose/hub/config/` gethomepage YAMLs were purged and the
    runtime-state paths gitignored. What remains is
    `.local/bin/mbsync-notify.sh`, still built into a
    `writeShellScriptBin` by `nix/modules/user/home.nix`; drop that
    wrapper and its `mandragora-pkg-diff` filter entry, then delete
    the script.

## Operations and resilience

26. **Ship the backup tiers.**
    [`persistence.md`](persistence.md) ranks user data and sketches
    backup tiers, and nothing is shipped — the box one disk failure
    away from losing everything the impermanence design says matters.
    Automate restic/borg for `/persistent` + `/home/m` per the
    ranking, and add a scheduled age-key lifeboat verification so key
    recovery is tested, not assumed.

27. **Move runtime services off live repo paths.**
    Twelve-plus modules point running services at
    `/persistent/mandragora/...` (claude-web, gource-renderer,
    gpu-status, bots, axon, zsh, home). A mid-rebase repo or a
    worktree checkout changes what running units execute — the
    opposite of declarative. Load sources into the store
    (`builtins.readFile` / path interpolation, already the repo norm)
    and let `restartTriggers` handle change propagation.

28. **Package cc-lens declaratively.**
    `nix/modules/desktop/cc-lens.nix` clones and builds from GitHub at
    service start — network-dependent first boot, unpinned revision,
    imperative build. Pin it as a flake input and build it in the
    derivation like every other custom package.

29. **Harden keystats privacy.**
    The SQLCipher keylog DB is the highest-sensitivity artifact on the
    box. Document its threat model next to
    [`secrets.md`](secrets.md), add retention (rotate/expire raw
    events after aggregation), and verify the cipher key never lands
    in the journal or process args.

30. **Single-writer discipline for the watch judge.**
    The containerized qwen3 judge and the desktop gemini bridge both
    write verdicts into the same sqlite DB, racing on the shared
    file. Route all writes through one queue (or split the DBs and
    merge in the reader) so verdicts stop depending on scheduling
    luck.
