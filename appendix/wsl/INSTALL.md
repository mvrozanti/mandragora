# Installing Mandragora-WSL on a fresh Windows 11 host

Single one-liner. Open an elevated PowerShell (Windows Terminal as
admin works) and:

```powershell
iex (iwr https://raw.githubusercontent.com/mvrozanti/mandragora/master/appendix/wsl/install.ps1)
```

The orchestrator will:

1. Apply Windows cosmetic + privacy tweaks (dark theme, hide
   widgets/search, disable telemetry basics).
2. Enable the `Microsoft-Windows-Subsystem-Linux` and
   `VirtualMachinePlatform` Windows features.
3. **Reboot automatically.** A `RunOnce` registry entry resumes the
   installer the next time you log in — just sign back in and wait.
4. Download and `msiexec /qn` the WSL2 MSI from
   `github.com/microsoft/WSL/releases/latest`. (The inbox `wsl
   --install` stub does not work without Microsoft Store auth.)
5. Download the latest NixOS-WSL tarball and `wsl --import` it as a
   distro called `NixOS`.
6. Inside NixOS-WSL: clone the mandragora repo to `/etc/nixos/mandragora`
   and run `nixos-rebuild switch --flake .#mandragora-wsl --impure`.

When the orchestrator prints `==> mandragora-wsl install complete.`
your shell is ready:

```powershell
wsl -d NixOS
```

You will land as user `m` in zsh with the mandragora prompt, the
shared CLI config (zsh history + autosuggestions, tmux 3.6, lf,
neovim, git/gh/go, fzf/ripgrep/fd/bat/eza/zoxide), and the agent
skills wired up under `~/.claude/skills/` and `~/.gemini/skills/`.

## Picking up where you left off

The orchestrator persists progress in `C:\mandragora-install-state.txt`
and re-runs the same one-liner from there. If a step fails, fix the
underlying issue and re-run; you skip everything that already
succeeded.

To force a fresh re-install (e.g. testing on a snapshot rollback):

```powershell
Remove-Item C:\mandragora-install-state.txt, C:\mandragora-install.ps1 -Force -ErrorAction Ignore
wsl --unregister NixOS
```

## Choosing a different fork or branch

```powershell
$env:MANDRAGORA_REPO = 'https://github.com/yourfork/mandragora.git'
iex (iwr https://raw.githubusercontent.com/yourfork/mandragora/master/appendix/wsl/install.ps1)
```

## Known limitations

- **No GUI / desktop config.** mandragora-wsl is a CLI-only host;
  Hyprland, waybar, rofi, the bots, the GPU stack, and similar live
  in `mandragora-desktop` and are intentionally not pulled in.
- **Pywal warning on first nvim launch.** The desktop colorscheme
  expects pywal output that does not exist in WSL. Cosmetic; can be
  suppressed by editing `.config/nvim/colors/pywal.vim` later.
- **First run downloads ~250 MB of WSL MSI + ~1 GB NixOS-WSL tarball
  + lots of Nix store closure.** Expect 10-20 minutes on a fast
  connection.
- **`--impure` is required** for `nixos-rebuild` inside WSL because
  the NixOS-WSL module reads runtime info (kernel version, etc.).
