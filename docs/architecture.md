# Architecture

**Type:** infra (NixOS flake, single host)
**Architecture pattern:** Modular flake with strict separation of concerns

## 0. Vision

A "second skin" Linux environment — a perfectly tailored, high-performance
NVIDIA/Wayland workstation built for creative production, development, and
system sovereignty. Hardware and software are in a continuous loop of
aesthetic and functional refinement. The metric of success is that the
whole system is comprehensible to a single individual.

## 1. Executive summary

The system is a single-host NixOS flake. There is one machine
(`mandragora-desktop`), one user (`m`), and one nixosConfiguration. Every
runtime concern is expressed as a Nix module under `modules/`. The host
composition file (`hosts/mandragora-desktop/default.nix`) imports those
modules, and the flake (`flake.nix`) wires everything to pinned inputs.

The defining architectural choice is **impermanence**: the root filesystem is
wiped on every boot, and only `/nix`, `/persistent`, and `/home/m`
(bind-mounted from `/persistent/home/m`) survive. This forces every piece of
runtime state to be either ephemeral or explicitly declared in
`modules/core/impermanence.nix`. The git remote serves as the persistence
mechanism for the configuration source itself.

## 2. Technology Stack

| Category              | Technology                          | Version / Source                   |
| --------------------- | ----------------------------------- | ---------------------------------- |
| OS                    | NixOS                               | nixpkgs `nixos-unstable`           |
| Build/config language | Nix (flakes, `nix-command`)         | system default                     |
| Bootloader            | systemd-boot                        | system default                     |
| Kernel                | `linuxPackages_zen`                 | nixpkgs                            |
| Filesystem            | Btrfs (subvolumes)                  | kernel                             |
| Compositor            | Hyprland                            | nixpkgs                            |
| Display server        | Wayland (no X11 fallback)           | system                             |
| Display manager       | SDDM                                | nixpkgs                            |
| GPU driver            | NVIDIA proprietary                  | 570.x beta                         |
| User home             | home-manager                        | github:nix-community/home-manager  |
| Secrets               | sops-nix + age                      | github:Mic92/sops-nix              |
| Impermanence          | impermanence                        | github:nix-community/impermanence  |
| Local LLM runtime     | (declared in `modules/core/ai-local.nix`) | nixpkgs                      |
| Monitoring            | Prometheus + Grafana                | nixpkgs                            |

## 3. Architecture Pattern

### Composition shape

```
flake.nix
└─ nixosConfigurations.mandragora-desktop
   └─ hosts/mandragora-desktop/default.nix
      ├─ pkgs/overlays.nix                    (custom overlays)
      ├─ modules/core/*.nix                   (OS-level concerns)
      ├─ modules/desktop/*.nix                (GUI session)
      ├─ modules/user/home-manager.nix        (loads home-manager → home.nix)
      └─ modules/audits/default.nix           (state-drift checks)
```

### One concern per module

The codebase deliberately favors many small files over a few big ones. The
unit of organization is `modules/<area>/<thing>.nix` — for example
`modules/desktop/keyledsd.nix` exists as a separate file rather than a
section inside a generic `modules/desktop/peripherals.nix`. The rule is
roughly "one screen of code per module"; if a module grows past that, it
gets split.

### Language purity

Nix code lives in `.nix` files. Shell, Python, Lua, and CSS live at the repo
root in XDG-mirrored directories (`.config/`, `.local/bin/`, `snippets/`),
and the corresponding `.nix` file consumes them via:

- `builtins.readFile ../../.config/<app>/<file>.conf`
- `pkgs.writeShellScript "<name>" (builtins.readFile ../../.local/bin/<script>.sh)`
- `pkgs.writeScript "<name>" (builtins.readFile ../../snippets/<file>.lua)`

This makes non-Nix code editable with the right syntax highlighting, lintable
by its own tooling, and reusable outside the flake context if needed.

### No comments

Logic is expected to be self-documenting through naming and structure.
Comments must be removed when editing — including comments in
shell/Python/Lua. The rule is enforced for both Nix and non-Nix code.

## 4. Storage & Filesystem Layout

The system runs on a single 2 TB NVMe with a Btrfs-heavy partition scheme.

| Partition / Subvolume      | Mount                | Purpose                                           | Size       |
| -------------------------- | -------------------- | ------------------------------------------------- | ---------- |
| ESP                        | `/boot`              | systemd-boot, ~30 boot generations                | 4 GB FAT32 |
| Swap                       | (swap)               | Hibernation                                       | 32 GB      |
| Btrfs `root-blank`         | _(never mounted)_    | Clean seed for impermanence wipe                  | shared     |
| Btrfs `root-active`        | `/`                  | Ephemeral root, wiped on every boot               | shared     |
| Btrfs `nix`                | `/nix`               | Nix store, generations                            | shared     |
| Btrfs `persistent`         | `/persistent`        | Home, secrets, system state                       | shared     |

Total Btrfs pool: ~1.9 TB. All persistent subvolumes share the pool; Btrfs
quotas and snapshots manage them.

The home directory `/home/m` is bind-mounted from `/persistent/home/m` —
meaning every file under `~` survives, but `~` itself is _structurally_ not
on the root subvolume. This is intentional: it means an accidental wipe of
`/` cannot take user data with it.

### What lives in `/persistent`

| Path | Content |
| ---- | ------- |
| `/persistent/home/m` | All user data (~500 GB) |
| `/persistent/secrets/` | age key for sops-nix (`keys.txt`) |
| `/persistent/var/log` | System logs |
| `/persistent/var/lib/nixos` | NixOS state |
| `/persistent/etc/NetworkManager/system-connections` | WiFi credentials |
| `/persistent/etc/machine-id` | Stable systemd machine identity |
| `/persistent/var/lib/bluetooth` | Bluetooth pairing state |

The authoritative whitelist is `modules/core/impermanence.nix`.

## 5. Impermanence Mechanism

On every boot:

1. systemd initrd service runs.
2. The active root subvolume (`root-active`) is deleted.
3. A snapshot of the clean seed (`root-blank`) is taken into `root-active`.
4. The boot continues with a pristine `/`.

The `impermanence` flake input provides the module that declares which paths
under `/` should be bind-mounted from `/persistent` — for example
`/var/lib/<service>`, `/etc/<some-runtime-state>`, `/home/m` itself.

**Failure mode:** any service that writes runtime state outside the declared
persistent paths will silently lose that state at the next boot. The
`modules/audits/strays.sh` audit tries to catch this.

**The discipline:** before adding any service that writes state, check
`modules/core/impermanence.nix` and add the path. There is no other way.

## 6. Secrets Architecture

| Component             | Location                                              |
| --------------------- | ----------------------------------------------------- |
| Encrypted secrets     | `secrets/secrets.yaml` (committed to git)             |
| Encryption format     | sops + age                                            |
| Decryption key        | `/persistent/secrets/keys.txt` (root-only, persisted) |
| Wiring                | `modules/core/secrets.nix`                            |
| Reference syntax      | `config.sops.secrets."<path>".path`                   |
| Backup                | External USB + Seafile + Oracle VPS                   |

To add a new secret:

1. `sops secrets/secrets.yaml` — opens decrypted in editor.
2. Add the secret under a sensible key.
3. In `modules/core/secrets.nix`, declare it under `sops.secrets`.
4. Reference it elsewhere via `config.sops.secrets."<path>".path` (this gives
   the runtime path to the decrypted file).
5. Rebuild.

Plain-text secrets in `.nix` files are **forbidden**. There is no exception.

## 7. Display & Theming Pipeline

### Hardware stack

- GPU: NVIDIA RTX 5070 Ti, proprietary 570.x beta drivers.
- Display server: Wayland with the GBM backend.
- Compositor: Hyprland.
- Display manager: SDDM (Wayland-capable).
- No X11 fallback. The constraint is firm.

### Theming flow

A single source wallpaper drives the entire color scheme:

1. Wallpaper file is selected (manually or via a wallpaper picker; partial
   QuickShell-based picker — design notes archived to
   `~/wallpaper-picker-notes.md`, completion uncertain).
2. A pywal-style extractor produces a `colors.json` palette.
3. Templates injected via home-manager render that palette into:
   - Hyprland (`.config/hypr/`)
   - Kitty terminal
   - Neovim colorscheme
   - Waybar (`snippets/waybar-style.css` + `.config/waybar/`)
   - GTK theme

The pipeline is the reason theming feels coherent across the desktop without
manual tweaking — every component reads from the same generated palette
file.

## 8. Boot Sequence

1. Firmware (UEFI) splash.
2. systemd-boot menu (up to 10 generations retained).
3. Kernel + initrd.
4. Initrd runs the impermanence wipe (delete `root-active`, snapshot
   `root-blank`).
5. Mounts `/nix`, `/persistent`, bind-mount `/home/m`.
6. systemd userspace.
7. SDDM directly (no Plymouth splash).
8. User login → Hyprland session → home-manager-managed services start.

## 9. Module Inventory

### Core (`modules/core/`)

| Module                     | Responsibility                                              |
| -------------------------- | ----------------------------------------------------------- |
| `globals.nix`              | System packages, nix-ld, fonts                              |
| `boot.nix`                 | systemd-boot, kernel selection, kernel parameters           |
| `storage.nix`              | `fileSystems`, swap, mount options                          |
| `impermanence.nix`         | Persistent-paths whitelist (the reboot survival list)       |
| `persistence-vms.nix`      | VM disk persistence                                         |
| `secrets.nix`              | sops-nix wiring, age key path, secret declarations          |
| `security.nix`             | SSH, firewall, polkit, sudo                                 |
| `graphics.nix`             | NVIDIA proprietary, Wayland environment variables           |
| `monitoring.nix`           | Prometheus + Grafana                                        |
| `ai-local.nix`             | Local LLM runtime                                           |
| `vm.nix`                   | libvirt / qemu host                                         |

### Desktop (`modules/desktop/`)

| Module             | Responsibility                                        |
| ------------------ | ----------------------------------------------------- |
| `hyprland.nix`     | Compositor enable + config wiring                     |
| `sddm.nix`         | Display manager (Wayland session, autologin → Hyprland, sddm-mandragora theme) |
| `kdeconnect.nix`   | Phone bridge                                          |
| `keyd.nix`         | Capslock ↔ Esc remap (kernel-level)                  |
| `keyledsd.nix`     | Logitech keyboard LED control                         |
| `openrgb.nix`      | Generic RGB device control                            |
| `rival-mouse.nix`  | SteelSeries Rival USB power-state udev rule           |
| `ydotool.nix`      | uinput-based input synthesis (Wayland-safe xdotool)   |
| `seafile.nix`      | Self-hosted sync client                               |
| `steam.nix`        | Steam + gamemode                                      |
| `minecraft.nix`    | Minecraft launcher / server                           |

### User (`modules/user/`)

| Module               | Responsibility                                              |
| -------------------- | ----------------------------------------------------------- |
| `home-manager.nix`   | Enables home-manager NixOS module, imports `home.nix`       |
| `home.nix`           | User packages, `programs.*`, theming integration            |
| `zsh.nix`            | zsh config, plugins, aliases (consumes `snippets/aliases.zsh`) |
| `tmux.nix`           | tmux config (consumes `.config/tmux/tmux.conf`)             |
| `waybar.nix`         | Waybar config (consumes `.config/waybar/`, `snippets/waybar-*`) |
| `lf.nix`             | lf file manager                                             |
| `services.nix`       | User systemd services                                       |
| `bots.nix`           | Telegram-bridged bots (im-gen Flux, llm-via-telegram)       |
| `skills.nix`         | Wires `agent-skills/{handoff,pickup,nrp}` into `~/.claude/skills` and `~/.gemini/skills` |
| `minecraft.nix`      | User-side Minecraft (PrismLauncher etc.)                    |
| `zx-dirs.nix`        | XDG user directories                                        |

### Audits (`modules/audits/`)

| File                | Responsibility                                              |
| ------------------- | ----------------------------------------------------------- |
| `default.nix`       | Audit module entry                                          |
| `strays.sh`         | Detects state outside declared persistent paths             |

## 10. Custom Packages (`pkgs/`)

| Package         | Purpose                                                       |
| --------------- | ------------------------------------------------------------- |
| `overlays.nix`  | Wires every overlay into the host's nixpkgs instance          |
| `claude-code/`  | Anthropic Claude Code CLI (locally packaged)                  |
| `du-exporter/`  | Custom Prometheus exporter for disk-usage metrics             |
| `rtk/`          | Custom tooling                                                |

To add a new local package: create `pkgs/<name>/default.nix` and register it
in `pkgs/overlays.nix`.

## 11. Development Workflow (Architectural)

```
Edit (anywhere — repo is bind-mounted at /etc/nixos/mandragora and /persistent/mandragora)
  → Rebuild  (`sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop`)
  → Verify   (test the changed feature directly)
  → Commit   (`git add -A && git commit && git push`, or `mandragora-switch` alias)
```

There is no test suite. Verification is empirical — does the feature work?
Does the audit pass? Does the system reboot cleanly?

The repo lives at two paths simultaneously:
- `/etc/nixos/mandragora/` — the canonical path consumed by `nixos-rebuild`.
- `/persistent/mandragora/` — same files, bind-mounted; convenient when
  working from `/persistent`.

Both are the same git working tree.

## 12. Deployment Architecture

There is no remote deployment. The "deploy" is `nixos-rebuild switch` on the
machine itself. For full reinstall (replacement hardware, new disk, etc.),
the procedure is:

1. Boot from a NixOS live USB.
2. Run `install/format-drive.sh` (Btrfs partition + subvolume layout).
3. Run `install/mount-install.sh` (mounts subvolumes for the install).
4. Run `install/bootstrap-age-key.sh` (imports the age key from external USB).
5. Run `install/install.sh` (`nixos-install --flake .#mandragora-desktop`).
6. Reboot, log in, verify.

See [`../install/INSTALL.md`](../install/INSTALL.md) for the runbook.

## 13. Testing Strategy

There is no automated test suite. The closest things are:

- **`modules/audits/`** — shell-script audits run periodically on the host
  to detect state drift, stray files, and imperative state.
- **`nixos-rebuild test`** — applies a configuration without making it the
  boot default, useful for testing risky changes.
- **`nixos-rebuild dry-run`** / `dry-activate` — validates the configuration
  evaluates and would activate.
- **Empirical verification** — for any change, the user tests the feature
  directly and notes the result in the handoff system (`~/.ai-shared/handoffs/`).

The deliberate absence of CI is appropriate for a single-host config: there
is no team, no PR review pipeline, and the only "production" is the user's
own desktop, where empirical verification is immediate.

## 14. Hard constraints (architectural invariants)

These cannot be relaxed without changing the project's fundamental shape:

1. **Declarative supremacy** — every change is a Nix expression. No
   `pacman`, `chmod`, `systemctl enable` as solutions.
2. **Language purity** — non-Nix code lives in XDG-mirrored repo
   directories, referenced via `builtins.readFile`.
3. **No comments** — anywhere.
4. **Zero plain-text secrets** — sops-nix + age only.
5. **Impermanence** — only `/nix`, `/persistent`, `/home/m` survive. Any
   change must answer: "does this survive reboot without touching Nix?"
6. **NVIDIA + Wayland only** — no X11 fallback.
7. **Out of the box** — every program works on first launch with zero setup.
8. **No FDE** — main drive intentionally unencrypted.

The canonical statement is in [`../AGENTS.md`](../AGENTS.md).

## 15. External Systems

| System | Relationship |
| ------ | ------------ |
| `arch-slave` | Reference machine + bulk storage + Seafile server. Stays Arch+pacman; not managed by this flake. Seafile runs here; Mandragora connects as a client. Backup logic lives in Mandragora Nix config (push, not pull). |
| Oracle VPS | Future use — not currently hosting anything. Intended as off-site mirror for critical data. |
| Notebook | Future NixOS host — not yet defined in the flake. |

## 16. References

- [`../AGENTS.md`](../AGENTS.md) — hard constraints (load first)
- [`./hardware.md`](./hardware.md) — hardware specs and peripheral control
- [`./workflow.md`](./workflow.md) — edit/rebuild/verify/commit workflow
- [`./persistence.md`](./persistence.md) — what survives reboot, why
- [`./secrets.md`](./secrets.md) — sops-nix wiring
