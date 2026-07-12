# Architecture

**Type:** infra (NixOS flake, multi-target)
**Architecture pattern:** Modular flake with strict separation of concerns

## 0. Vision

A "second skin" Linux environment — a perfectly tailored, high-performance
NVIDIA/Wayland workstation built for creative production, development, and
system sovereignty. Hardware and software are in a continuous loop of
aesthetic and functional refinement. The metric of success is that the
whole system is comprehensible to a single individual.

## 1. Executive summary

The flake centers on one workstation (`mandragora-desktop`) but ships four
targets for one user (`m`). Every runtime concern is expressed as a Nix
module under `nix/modules/`. Each host's composition file
(`nix/hosts/<host>/default.nix`) imports those modules, and the flake
(`flake.nix`) wires everything to pinned inputs.

| Target | Kind | Built by |
| ------ | ---- | -------- |
| `mandragora-desktop` | NixOS workstation (the primary host) | `nixosConfigurations.mandragora-desktop` |
| `mandragora-wsl` | NixOS-WSL guest | `nixosConfigurations.mandragora-wsl` |
| `mandragora-usb` | NixOS live/installer image | `nixosConfigurations.mandragora-usb` + `packages.usbImage` (raw-efi generator) + `apps.refiner` (QEMU boot-test harness) |
| `mandragora-vps` | Oracle Linux ARM VPS — **not a NixOS host** | `homeConfigurations."m@mandragora-vps"` (aarch64 home-manager) + docker-compose stacks under `nix/hosts/mandragora-vps/compose/` |

Only `mandragora-desktop` is described in the sections below; it is the one
machine that runs the full impermanence/desktop/theming stack. The vps is
managed as a home-manager profile plus caddy-fronted compose stacks, not via
`nixos-rebuild`.

The defining architectural choice is **impermanence**: the root filesystem is
wiped on every boot, and only `/nix`, `/persistent`, and `/home/m`
(bind-mounted from `/persistent/home/m`) survive. This forces every piece of
runtime state to be either ephemeral or explicitly declared in
`nix/modules/core/impermanence.nix`. The git remote serves as the persistence
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
| Local LLM runtime     | (declared in `nix/modules/core/ai-local.nix`) | nixpkgs                      |
| Monitoring            | Prometheus + Grafana                | nixpkgs                            |

## 3. Architecture Pattern

### Composition shape

```
flake.nix
├─ nix/modules/shared/*.nix                       (cross-host: profile, overlays, zsh, nvim, build-checks)
└─ nixosConfigurations.mandragora-desktop
   └─ nix/hosts/mandragora-desktop/default.nix
      ├─ nix/modules/core/*.nix                   (OS-level concerns)
      ├─ nix/modules/desktop/*.nix                (GUI session)
      ├─ nix/modules/services/*.nix               (self-hosted web/GPU services)
      ├─ nix/modules/user/home-manager.nix        (loads home-manager → home.nix)
      └─ nix/modules/audits/default.nix           (runtime state-drift checks)
```

The `nix/modules/shared/overlays.nix` set (which wires `nix/pkgs/`) is shared
across all NixOS targets via `flake.nix`'s `sharedModules`, not imported
per-host.

### One concern per module

The codebase deliberately favors many small files over a few big ones. The
unit of organization is `nix/modules/<area>/<thing>.nix` — for example
`nix/modules/desktop/keyledsd.nix` exists as a separate file rather than a
section inside a generic `nix/modules/desktop/peripherals.nix`. The rule is
roughly "one screen of code per module"; if a module grows past that, it
gets split.

### Language purity

Nix code lives in `.nix` files. Shell, Python, Lua, and CSS live at the repo
root in XDG-mirrored directories (`.config/`, `.local/bin/`, `nix/snippets/`),
and the corresponding `.nix` file consumes them via:

- `builtins.readFile ../../.config/<app>/<file>.conf`
- `pkgs.writeShellScript "<name>" (builtins.readFile ../../.local/bin/<script>.sh)`
- `pkgs.writeScript "<name>" (builtins.readFile ../../nix/snippets/<file>.lua)`

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

The authoritative whitelist is `nix/modules/core/impermanence.nix`.

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
`nix/modules/audits/strays.sh` audit tries to catch this.

**The discipline:** before adding any service that writes state, check
`nix/modules/core/impermanence.nix` and add the path. There is no other way.

## 6. Secrets Architecture

| Component             | Location                                              |
| --------------------- | ----------------------------------------------------- |
| Encrypted secrets     | `secrets/secrets.yaml` (committed to git)             |
| Encryption format     | sops + age                                            |
| Decryption key        | `/persistent/secrets/keys.txt` (root-only, persisted) |
| Wiring                | `nix/modules/core/secrets.nix`                            |
| Reference syntax      | `config.sops.secrets."<path>".path`                   |
| Backup                | External USB + Seafile + Oracle VPS                   |

To add a new secret:

1. `sops secrets/secrets.yaml` — opens decrypted in editor.
2. Add the secret under a sensible key.
3. In `nix/modules/core/secrets.nix`, declare it under `sops.secrets`.
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
   - Waybar (`nix/snippets/waybar-style.css` + `.config/waybar/`)
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

Modules are grouped by concern under `nix/modules/<area>/`. Rather than
enumerate every file (the tree grows faster than this doc), each directory is
summarized by its role and a few representative modules; read the directory
itself for the current full list.

### Core (`nix/modules/core/`)

OS-level system concerns. Boot and storage (`boot.nix`, `storage.nix`,
`impermanence.nix`, `persistence-vms.nix`), security and networking
(`secrets.nix`, `security.nix`, `wifi.nix`, `tailscale.nix`), hardware and
runtime (`graphics.nix`, `ai-local.nix`, `vm.nix`, `gdrive.nix`), and
observability/maintenance (`monitoring.nix` — Prometheus + Grafana,
`nix-auto-update.nix`, `vuln-scan.nix`, `oom-protection.nix`,
`oom-forensics.nix`). `impermanence.nix` holds the reboot-survival whitelist;
`secrets.nix` wires sops-nix and the age key path.

### Desktop (`nix/modules/desktop/`)

The GUI session and peripherals. Session (`hyprland.nix`, `sddm.nix`,
`input-method.nix`), input/LED/RGB hardware (`keyd.nix`, `keyledsd.nix`,
`keystats.nix`, `openrgb.nix`, `rival-mouse.nix`, `ydotool.nix`), sync and
bridges (`seafile.nix`, `syncthing.nix`, `kdeconnect.nix`,
`phone-archiver.nix`), gaming (`steam.nix`, `wine-gaming.nix`, `minecraft.nix`,
`mt5.nix`, `ue5.nix`), and Claude-Code desktop integrations (`cc-lens.nix`,
`claudecodebrowser.nix`, `watch-judge.nix`). One file per device/concern is
the rule (e.g. `keyledsd.nix` is its own module, not a section of a generic
peripherals file).

### Services (`nix/modules/services/`)

Self-hosted web and GPU-backed services that run on the desktop host — image
generation (`im-gen-web.nix`, `im-gen-slice.nix`, `im-gen-cipher.nix`),
LLM/web frontends (`open-webui.nix`, `ollama-context-proxy.nix`,
`llm-visualizer.nix`, `ttyd.nix`, `claude-web.nix`), media and misc web apps
(`mympd.nix`, `ytdl-web.nix`, `vtag-web.nix`, `emotion-web.nix`,
`edgard-web.nix`, `slither-io.nix`, `gource-renderer.nix`), and the
`hub-services.nix` aggregator.

### User (`nix/modules/user/`)

home-manager scope. `home-manager.nix` enables the NixOS module and imports
`home.nix` (the large user-packages/`programs.*`/theming file). Program config
that consumes XDG-mirrored files (`zsh.nix`, `tmux.nix`, `waybar.nix`,
`yazi.nix`), user systemd units (`services.nix`), agent/bot integrations
(`bots.nix` — Telegram-bridged im-gen Flux + llm-via-telegram, `axon.nix`,
`autoclaude.nix`, `skills.nix`, `nb-vault-sync.nix`), the wofi/rofi menus
(`gpu-menu.nix`, `monitor-menu.nix`, `rss-menu.nix`, `security-menu.nix`,
`weather-menu.nix`), and `zx-dirs.nix` (XDG user directories). `skills.nix`
wires `agent-skills/{handoff,pickup,nrp}` into `~/.claude/skills` and
`~/.gemini/skills`.

### Shared (`nix/modules/shared/`)

Cross-host modules loaded via `flake.nix`'s `sharedModules` list, so every
NixOS target gets them: `profile.nix`, `common-packages.nix`, `zsh.nix`,
`nvim.nix`, `overlays.nix` (wires `nix/pkgs/`), and `build-checks.nix` (the
flake `checks` guards — see §13).

### Audits (`nix/modules/audits/`)

Runtime state-drift checks for the running system: `default.nix` (module
entry, wires the periodic checks), `strays.sh` (detects state written outside
declared persistent paths), and `repo.nix` (packages `mandragora-audit` and
sets `core.hooksPath` for the repo-tier commit checks). The repo-tier check
suite itself lives at `.local/share/mandragora-audit/` — see §13 and
[`./audits.md`](./audits.md).

## 10. Custom Packages (`nix/pkgs/`)

Locally packaged derivations, wired into every NixOS target's nixpkgs via
`nix/modules/shared/overlays.nix` (which imports `nix/pkgs/overlays.nix`).
Representative packages: `claude-code/` (Anthropic Claude Code CLI),
`du-exporter/` (custom Prometheus disk-usage exporter), `rtk/` (the token-saver
CLI proxy), `sddm-mandragora/` (the SDDM theme), `axon/`, `refiner/` (the USB
image QEMU boot-test harness behind `apps.refiner`), and `ue5/` (Unreal Engine
devShell, exposed as `devShells.ue5`).

To add a new local package: create `nix/pkgs/<name>/default.nix` and register it
in `nix/pkgs/overlays.nix`.

## 11. Development Workflow (Architectural)

```
Edit (anywhere — repo is bind-mounted at /etc/nixos/mandragora and /persistent/mandragora)
  → Rebuild  (`sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop`)
  → Verify   (test the changed feature directly)
  → Commit   (`git add -A && git commit && git push`, or `mandragora-switch` alias)
```

Verification combines automated gates with empirical checks: the pre-commit
hook runs the `mandragora-audit` repo checks on staged files, `flake.nix`
exposes build guards under `checks`, and beyond that — does the feature work?
Does the system reboot cleanly? See §13 for the full test/audit surface.

The repo lives at two paths simultaneously:
- `/etc/nixos/mandragora/` — the canonical path consumed by `nixos-rebuild`.
- `/persistent/mandragora/` — same files, bind-mounted; convenient when
  working from `/persistent`.

Both are the same git working tree.

## 12. Deployment Architecture

For `mandragora-desktop` there is no remote deployment — the "deploy" is
`nixos-rebuild switch` on the machine itself. The other targets deploy
differently: `mandragora-usb` is built to an image (`nix build .#usbImage`)
and boot-tested in QEMU (`nix run .#refiner`); `mandragora-vps` deploys as a
home-manager profile (`home-manager switch --flake .#m@mandragora-vps`) plus
`docker compose up` of the stacks under `nix/hosts/mandragora-vps/compose/`
(no nixos-rebuild — it is Oracle Linux).

For a full desktop reinstall (replacement hardware, new disk, etc.), the
procedure is:

1. Boot from a NixOS live USB.
2. Partition + lay out Btrfs subvolumes, mount them, generate the age key and
   encrypt secrets against it, then `nixos-install --flake .#mandragora-desktop`
   against the mounted target. The scripts driving each step live under
   `docs/install/` and `nix/hosts/mandragora-usb/install/`.
3. Reboot, log in, verify.

See [`install/INSTALL.md`](install/INSTALL.md) for the step-by-step runbook.

## 13. Testing Strategy

There is no cloud CI pipeline, but several automated test/gate layers run
locally:

- **Repo audit suite (`mandragora-audit`)** — a deterministic, errors-only
  shell suite at `.local/share/mandragora-audit/` that enforces the AGENTS.md
  non-negotiables mechanically (no-extraconfig, doc-links, conventional-commits,
  hyprland-config, hub-tile, no-projects-in-local-share, language-purity,
  statix, deadnix, shellcheck). It runs on staged files via the pre-commit/commit-msg
  hooks and in full before `mandragora-switch` stages. Full reference:
  [`./audits.md`](./audits.md).
- **Flake build guards (`checks`)** — `flake.nix` exposes `checks.<system>`
  (closure-size, profile-eval, sops-key guards from
  `nix/modules/shared/build-checks.nix`) that fail evaluation on regressions.
- **USB installer tests** — five `bats` suites under
  `nix/hosts/mandragora-usb/tests/install/` (`test_detect`, `test_format`,
  `test_install`, `test_lib`, `test_render_config`) cover the install scripts.
- **Runtime audits (`nix/modules/audits/`)** — shell audits run periodically
  on the host to detect state drift, stray files, and imperative state.
- **`nixos-rebuild test` / `dry-run` / `dry-activate`** — apply or validate a
  configuration without making it the boot default; useful for risky changes.
- **Empirical verification** — for anything the above can't gate, the user
  tests the feature directly and notes the result in the handoff system
  (`~/.ai-shared/handoffs/`).

The absence of a *cloud* CI pipeline is appropriate for a solo config: there
is no team and no PR review pipeline, and the only desktop "production" is the
user's own machine, where empirical verification is immediate. The gates that
do exist are the ones that catch agent mistakes before they land.

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
| Oracle VPS (`mandragora-vps`) | Solo-owned production ARM VPS on Oracle Linux (**not** NixOS). Managed as the `homeConfigurations."m@mandragora-vps"` home-manager profile plus caddy-fronted `docker compose` stacks under `nix/hosts/mandragora-vps/compose/` (the `*.mvr.ac` subdomains). Also an off-site secrets/backup mirror. |
| Notebook | Future NixOS host — not yet defined in the flake. |

## 16. References

- [`../AGENTS.md`](../AGENTS.md) — hard constraints (load first)
- [`./hardware.md`](./hardware.md) — hardware specs and peripheral control
- [`./workflow.md`](./workflow.md) — edit/rebuild/verify/commit workflow
- [`./persistence.md`](./persistence.md) — what survives reboot, why
- [`./secrets.md`](./secrets.md) — sops-nix wiring
