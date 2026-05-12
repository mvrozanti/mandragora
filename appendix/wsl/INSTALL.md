# Installing Mandragora-WSL on a Windows 11 host

## Prerequisite: WSL2 must already be installed

This installer is admin-free. It runs entirely as the regular user
and assumes WSL2 is already present on the host. The orchestrator
hard-checks `wsl --version` upfront and aborts with a clear error if
it is missing.

If WSL2 is **not** installed, run this once on the target host (admin
PowerShell, reboot after):

```powershell
wsl --install --no-distribution
```

Then reboot and proceed with the one-liner below.

## The one-liner

Open a regular PowerShell (no need to "Run as Administrator") and:

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
   no Cortana, no telemetry, no widgets. *This is the only phase
   that triggers UAC, and only when opted-in.*
2. Download the latest NixOS-WSL tarball and `wsl --import` it as a
   **new sibling distro called `NixOS`**. Existing `Ubuntu`,
   `Debian`, `Fedora`, etc are left alone.
3. Inside NixOS-WSL: clone the mandragora repo to
   `/etc/nixos/mandragora` and run `nixos-rebuild switch --flake
   .#mandragora-wsl --impure`.

## Conflicts with pre-existing files

Anywhere a previous install left state — the `NixOS` distro, the
downloaded `nixos-wsl.tar.gz` tarball, the `/etc/nixos/mandragora`
checkout inside WSL — the installer **prompts before replacing**:

```
    'WSL distro "NixOS"' already exists. Replace? [Y]es / [N]o / [A]ll / N[o]ne:
```

- `Y` — replace this one only
- `N` — keep this one, prompt on the next conflict
- `A` — replace this and every subsequent conflict (yes-to-all)
- `O` — keep this and every subsequent conflict (no-to-all)

For automation, set `MANDRAGORA_REPLACE=all` or `MANDRAGORA_REPLACE=none`
in the environment to skip prompts entirely.

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
$env:MANDRAGORA_RICE     = '1'      # opt in to Windows cosmetic / privacy registry tweaks (UAC)
$env:MANDRAGORA_PERSONAL = '1'      # opt in to mvrozanti's personal config (git identity + aerc/khal/notmuch dotfiles)
$env:MANDRAGORA_FORCE    = '1'      # bypass the managed-device safety prompt
$env:MANDRAGORA_REPO     = 'https://github.com/<fork>/mandragora.git'
$env:MANDRAGORA_REPLACE  = 'all'    # auto-answer every conflict prompt with Yes (or 'none' for No)
```

## What about credentials / PII on a work machine?

The install itself stores **zero passwords or credentials** anywhere
on Windows or in WSL. Specifically:

- No passwords saved to Windows credential store
- No SSH keys generated or copied in
- No sudo password set — the WSL `m` user has passwordless sudo via
  the `wheel` group (`wheelNeedsPassword = false`)
- `gh auth` credential helper is **off by default** (only enabled
  with `MANDRAGORA_PERSONAL=1`)
- No personal email / git identity is baked in by default — the
  default git config has no `user.name` / `user.email`, you'll set
  yours later or the host config will refuse commits with a clear
  error
- No `.config/aerc`, `.config/khal`, `.config/notmuch` dotfiles
  are installed by default — those bear personal email addresses
  and are only added when you explicitly set `MANDRAGORA_PERSONAL=1`

**What lives on the work PC after install (default mode):**

- The `NixOS` WSL distro, stored in
  `C:\Users\<you>\AppData\Local\Packages\<wsl-package>\LocalState\` or
  `C:\WSL\NixOS\` — IT can read this filesystem (or `wsl --export`
  it). Contains the mandragora repo (public) and Nix store closures.
- A bookkeeping registry key (`HKCU:\SOFTWARE\Mandragora`) with the
  install stage. Deleted when the install reaches `done`.
- A transcript at `%LOCALAPPDATA%\Mandragora\install.log`. Deleted
  when the install reaches `done`.

**What you should still be careful about after install:**

Anything you do *inside* WSL goes into a filesystem the work PC can
read. If you `gh auth login`, run `aerc` with passwords typed in,
git-clone with embedded tokens, etc — those all land in WSL files
that IT could read. Use app-specific passwords, OAuth tokens scoped
to your personal accounts, or keep all secrets in `pass`/`gpg` with
keys you carry separately.

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

State lives in `HKCU:\SOFTWARE\Mandragora\InstallStage` and is also
inferred from the system (`wsl --list --quiet` for an existing
`NixOS` distro). Re-running the same one-liner is **idempotent** —
it picks up where it left off, prompts before replacing any
pre-existing artefact, and on a fully installed system does just
`git pull && nixos-rebuild switch` inside WSL.

To force a fresh re-install (e.g. testing on a snapshot rollback):

```powershell
Remove-Item HKCU:\SOFTWARE\Mandragora -Recurse -Force -ErrorAction Ignore
Remove-Item $env:LOCALAPPDATA\Mandragora -Recurse -Force -ErrorAction Ignore
wsl --unregister NixOS
```

Or just re-run the one-liner and answer `A` (replace All) at the
first prompt.

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
