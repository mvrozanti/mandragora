# Routing through `rtk` for token savings

This is the full body of AGENTS.md Rule 13. AGENTS.md keeps a 3-line
summary; load this when you need the full subcommand list or rationale.

`rtk` is a context-window proxy installed at `/run/current-system/sw/bin/rtk`.
When you run a command whose output is going into your context, prefer
`rtk <subcmd>` over the raw tool. It strips noise (banners, progress
bars, repeated paths, ASCII tables) so the same information costs 60–90%
fewer tokens.

## Subcommands to route through rtk by default

Full set as of v0.37.2 — call `rtk --help` if unsure:

- **Filesystem / read:** `ls`, `tree`, `find`, `read`, `wc`, `diff`, `grep`
- **VCS / forge:** `git`, `gh`
- **Network:** `curl`, `wget`
- **Logs / errors:** `log`, `err`, `summary`, `smart`
- **Languages / build:** `cargo`, `npm`, `npx`, `pnpm`, `jest`, `vitest`, `tsc`, `lint`, `prettier`, `format`, `playwright`, `prisma`, `next`, `dotnet`, `pytest`, `mypy`, `ruff`, `rake`
- **Infra / cloud:** `docker`, `kubectl`, `aws`, `psql`
- **Data:** `json`, `env`

## Why

rtk was packaged and installed (`pkgs/rtk/default.nix`,
`modules/core/globals.nix`) but no agent contract referenced it, so the
proxy was dead code — every `git log`, `grep`, `cargo build`, etc. went
raw and burned context. Making the routing explicit closes that loop.

## How to apply

1. Default to `rtk <cmd>` when the command appears above. Pass native
   flags through unchanged (e.g. `rtk grep -rn pattern path/`,
   `rtk git log --oneline -20`, `rtk find . -name '*.nix'`).
2. If you need raw output (piping into another tool, scripting, or
   rtk's filtering loses information you specifically need), drop to
   the bare command and say so in your update.
3. The Bash tool auto-allows the `rtk <subcmd> *` patterns currently
   in `~/.claude/settings.local.json`; new subcommands may prompt the
   first time — approve and continue.
4. Don't bother with `rtk` for commands that already produce minimal
   output (e.g. `hyprctl`, single-unit `systemctl status`) — the proxy
   overhead is wasted there.
