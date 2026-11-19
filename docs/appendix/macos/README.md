# Appendix: mandragora-macos (nix-darwin on a work Mac)

`mandragora-macos` brings the shared CLI baseline (`nix/modules/shared/home-cli.nix`:
zsh + p10k, neovim, tmux, yazi, claude-code, rtk) to a work-issued Apple
Silicon Mac, with kitty and a few macOS defaults on top. It is the macOS
counterpart of [`../wsl/`](../wsl/README.md): same repo path, same local
`work` branch that is never pushed, same opt-in for personal tooling.

It is a `darwinConfigurations` output built with
[nix-darwin](https://github.com/nix-darwin/nix-darwin) and home-manager, not a
NixOS host. There is no impermanence, no sops identity and no desktop agent
context (`~/.ai-shared`) on this machine.

## Install

Requirements: Apple Silicon, an administrator account (Nix creates the
`/nix` volume once; on a managed Mac, request temporary admin from IT or the
Self Service / Privileges app). Then run, in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/mvrozanti/mandragora/master/docs/appendix/macos/bootstrap.sh | bash
```

For the personal slice (git identity, mail, calendar), set the variable on
the `bash` side of the pipe: `... | MANDRAGORA_PERSONAL=1 bash`. Export it in
your shell as well if later `nrs` runs should keep it.

The bootstrap ([`bootstrap.sh`](bootstrap.sh)) is safe to re-run. It logs to
`~/Library/Logs/mandragora-bootstrap.log` and does, in order:

1. Preflight: arm64, admin rights, one `sudo` prompt.
2. Installs Nix with the [Lix installer](https://lix.systems/install/) if
   absent (nix-darwin's recommendation, because it ships an uninstaller).
   nix-darwin then manages the Nix daemon itself.
3. Installs Homebrew if absent (casks only; cleanup is off, so nothing IT
   installed through brew is touched).
4. Clones the repo to `/etc/nixos/mandragora` and creates the local `work`
   branch (`pushRemote = no_push`).
5. Builds `darwinConfigurations.mandragora-macos` and switches to it. If
   nix-darwin refuses `/etc` files with content it does not recognise
   (typically IT-customised `/etc/zshrc` or `/etc/bashrc`), they are renamed
   to `*.before-nix-darwin`, listed, and the switch is retried. Diff them and
   port anything that matters (proxy variables, certificates).
6. Verifies: every core command resolves, the clipboard shims round-trip, and
   GNU coreutils come before the BSD tools in a login shell.

## Day to day

`nrs` (or `nrc`) runs `mandragora-macos-switch`: it refuses to run on
`master`, refuses untracked files (the flake cannot see them; stage the ones
you want by path), merges `origin/master` into `work`, then runs
`sudo darwin-rebuild switch --flake /etc/nixos/mandragora#mandragora-macos --impure`.

## Design notes

- **No hostname.** MDM owns the computer name; the config never sets
  `networking.hostName` or `computerName`. The flake output is always named
  explicitly.
- **No committed username.** The account name comes from `SUDO_USER` at
  switch time (`--impure`), so a corporate login never lands in this public
  repo. Pure evaluation on the desktop falls back to `m`.
- **GNU userland first.** coreutils, sed, grep, awk, findutils, tar, diffutils,
  flock and `iproute2mac` come before `/usr/bin`, so the shared shell config
  and scripts (`head -n -1`, `date -d`, `stat -c`, `timeout`, `ip`) work
  unchanged.
- **Wayland/X names map to macOS.** `wl-copy`/`wl-paste` use
  `pbcopy`/`pbpaste` (images through `pngpaste`), `xdg-open` uses `open`, and
  `notify-send` uses `osascript`. This mirrors the WSL clipboard shims.
- **Kept from rotting.** `mandragora-switch` on the desktop evaluates this
  host in its pre-flight, next to `mandragora-wsl`. A change that breaks the Mac
  blocks the push.

## Known gaps

- No tiling window manager yet (AeroSpace is the intended next step).
- `claude-resurrect.sh` reads `/proc`, so restoring Claude sessions in tmux
  does nothing here.
- `tmux-scratchpad` and `claude-backend-sync` are desktop-only, as on WSL.
- `trash-cli` uses `~/.local/share/Trash`, not the macOS Trash.
