---
type: index
tags: [atlas, index, modules]
---

# Modules

The Nix module tree. Hosts import these; modules import each other in a layered cake.

Up: [[../_MOC|Atlas MOC]]

## core/ — system foundations

- [[core/globals]] — networking, hostname
- [[core/boot]] — bootloader, kernel
- [[core/storage]] — btrfs, snapshots
- [[core/impermanence]] — root-wipe pattern
- [[core/graphics]] — NVIDIA, declares `gpu.vramGB`
- [[core/security]] — kernel hardening, firewall
- [[core/secrets]] — sops-nix integration
- [[core/ai-local]] — Ollama, gates on VRAM
- [[core/monitoring]] — Prometheus, GPU metrics
- [[core/vm]] — qemu/libvirt
- [[core/persistence-vms]] — VM persistence

## desktop/ — UI, gaming, hardware

- [[desktop/hyprland]] — Wayland compositor + Pipewire
- [[desktop/sddm]] — login manager (custom theme)
- [[desktop/kdeconnect]] — phone sync
- [[desktop/keyd]] — keyboard remapping
- [[desktop/keyledsd]] — RGB keyboard lighting
- [[desktop/ydotool]] — synthetic input
- [[desktop/openrgb]] — RGB device control
- [[desktop/rival-mouse]] — SteelSeries mouse driver
- [[desktop/seafile]] — self-hosted file sync
- [[desktop/steam]] — gaming
- [[desktop/minecraft-desktop|desktop/minecraft]] — Java edition launcher

## user/ — home-manager (user `m`)

- [[user/home-manager]] — HM integration shim
- [[user/home]] — package list + script bins
- [[user/zsh]] — shell + history
- [[user/zx-dirs]] — single source of truth for zX shortcuts
- [[user/lf]] — file manager (custom build)
- [[user/tmux]] — terminal multiplexer
- [[user/services]] — systemd user services (mpd, mbsync, transmission)
- [[user/bots]] — Telegram bot service
- [[user/waybar]] — top bar
- [[user/skills]] — BMAD skill ecosystem
- [[user/minecraft-user|user/minecraft]] — user-side mc config

## audits/ — health checks

- [[audits/default]] — health-check + strays activation

## See also

- [[../concepts/declarative-supremacy]]
- [[../concepts/language-purity]]
