# Installing Mandragora-WSL on a fresh Windows 11 host

Single one-liner. Open an elevated PowerShell (Windows Terminal as
admin works) and:

```powershell
iex (iwr https://raw.githubusercontent.com/mvrozanti/mandragora/master/appendix/wsl/install.ps1)
```

## What it does (and very deliberately does NOT do)

The orchestrator opens with a **preflight** that prints the host
state and waits 15s for you to abort with Ctrl-C:

- Detects domain-joined / Azure-AD-enrolled (managed) devices and
  **refuses to proceed** unless you set `MANDRAGORA_FORCE=1`. This
  is intentionally conservative — false positives are easy on
  personal Win 11 (any Microsoft account login can register an
  enrollment GUID). If you know the box is yours, set the env var.
- Lists existing WSL distros so you can confirm Ubuntu/Debian/etc
  will not be touched.
- Shows whether the cosmetic registry rice will run (default OFF).

Then it runs each phase. Defaults:

1. **(skipped by default)** Windows cosmetic + privacy registry
   tweaks. Opt in with `MANDRAGORA_RICE=1` if you want a dark theme,
   no Cortana, no telemetry, no widgets.
2. Enable `Microsoft-Windows-Subsystem-Linux` and
   `VirtualMachinePlatform` Windows features.
3. **Reboot automatically.** A `RunOnce` registry entry resumes the
   installer the next time you log in — just sign back in and wait.
4. Download and `msiexec /qn` the WSL2 MSI from
   `github.com/microsoft/WSL/releases/latest`. (The inbox `wsl
   --install` stub does not work without Microsoft Store auth.)
5. Download the latest NixOS-WSL tarball and `wsl --import` it as a
   **new sibling distro called `NixOS`**. Existing `Ubuntu`,
   `Debian`, `Fedora`, etc are left alone.
6. Inside NixOS-WSL: clone the mandragora repo to
   `/etc/nixos/mandragora` and run `nixos-rebuild switch --flake
   .#mandragora-wsl --impure`.

It will **not** touch:

- Any other WSL distro
- BitLocker, full-disk encryption, secure boot
- Corporate VPN, AV, MDM agent, group policy
- Windows user accounts, domain bindings, network settings

A full PowerShell transcript is written to
`%ProgramData%\Mandragora\install.log`. On any failure the
orchestrator prints the path so you can paste it back for help.

## Tunables

```powershell
$env:MANDRAGORA_RICE  = '1'   # opt in to Windows cosmetic / privacy registry tweaks
$env:MANDRAGORA_FORCE = '1'   # bypass the managed-device safety prompt
$env:MANDRAGORA_REPO  = 'https://github.com/<fork>/mandragora.git'
```

## After install

When the orchestrator prints `==> mandragora-wsl install complete.`
your shell is ready:

```powershell
wsl -d NixOS
```

You land as user `m` in zsh with the mandragora prompt, full CLI
config (zsh history + autosuggestions + p10k, tmux 3.6, lf, neovim
with all your plugins, git/gh/go, fzf/ripgrep/fd/bat/eza/zoxide,
direnv), the mail/calendar stack (aerc/notmuch/mbsync/khal), the
dev toolchain (cargo/rustc/cmake/make/kubectl/shellcheck/tokei),
crush (CLI AI), and the agent skills wired up under
`~/.claude/skills/` and `~/.gemini/skills/`.

## Picking up where you left off

State lives in `HKLM:\SOFTWARE\Mandragora\InstallStage` and is also
inferred from the system (registry-cleared post-feature-install
reboots are recovered from `wsl --version` / `wsl --list` /
`Get-WindowsOptionalFeature`). Re-running the same one-liner is
**idempotent** — it picks up where it left off, and on a fully
installed system does just `git pull && nixos-rebuild switch`
inside WSL.

To force a fresh re-install (e.g. testing on a snapshot rollback):

```powershell
Remove-Item HKLM:\SOFTWARE\Mandragora -Recurse -Force -ErrorAction Ignore
Remove-Item $env:ProgramData\Mandragora -Recurse -Force -ErrorAction Ignore
wsl --unregister NixOS
```

## Known limitations

- **No GUI / desktop config.** mandragora-wsl is a CLI-only host;
  Hyprland, waybar, rofi, the bots, the GPU stack, and similar live
  in `mandragora-desktop` and are intentionally not pulled in.
- **Pywal warning on first nvim launch.** The desktop colorscheme
  expects pywal output that does not exist in WSL. Cosmetic; can be
  suppressed by editing `.config/nvim/colors/pywal.vim` later.
- **First run downloads ~250 MB of WSL MSI + ~1 GB NixOS-WSL tarball
  + lots of Nix store closure.** Expect 15-25 minutes on a fast
  connection.
- **`--impure` is required** for `nixos-rebuild` inside WSL because
  the NixOS-WSL module reads runtime info (kernel version, etc.).
- **Email/git identity** in `modules/shared/home-cli.nix` and
  `home.file.".config/aerc"` is mvrozanti's. To use a different
  identity, fork the repo, edit those files, and point
  `MANDRAGORA_REPO` at your fork.
