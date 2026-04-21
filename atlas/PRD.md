# Mandragora NixOS: The Last System (PRD)

> "If a system is to serve the creative spirit, it must be entirely comprehensible to a single individual."

This document defines the core architecture, non-negotiable constraints, and the evolving vision for the Mandragora NixOS ecosystem.

## 1. Core Vision
To create a "second skin" Linux environment—a perfectly tailored, high-performance NVIDIA/Wayland workstation that serves as the final destination for system design and ricing.

## 2. The Main Profile (Mandragora)
*   **The Workstation:** A power-user environment focused on creative production, development, and system sovereignty.
*   **Performance Stack:**
    *   **GPU:** Proprietary NVIDIA drivers with Wayland-specific optimizations (modesetting, power management).
    *   **Compositor:** Hyprland-centric, inspired by `dusky` and `Hyprlust` for high-aesthetic tiling and animations.
*   **The Dynamic Rice:**
    *   **Pipeline:** Wallpaper -> Color Extraction -> Dynamic CSS/JSON injection for terminal, bar, and editor.
    *   **Theming:** Unified visual identity across all applications (Kitty, Neovim, Waybar, GTK).
*   **Observability:** AI-driven audits (Disk & Network) restricted to this profile.



## 4. Non-Negotiable Directives
*   **Multi-Machine Sovereignty:** Hardware profiles for Desktop and Notebook.
*   **Language Purity:** Nix-only logic; external snippets for all other languages.
*   **Hardware DNA:** NVIDIA GPU + Wayland Only.
*   **Total Version Control (GitHub/Local):** The source of truth is the most recent commit across GitHub or local hosts.
*   **Impermanence (Erase Your Darlings):** Root partition wipe on boot with selective persistence (mandatory).
*   **Zero-Secret Commits:** No plain-text secrets; `sops-nix` mandatory.
*   **Pure Linux Sovereignty:** No Windows; machine is a dedicated NixOS environment.
*   **Storage Hierarchy:** Desktop/Notebook (Main) + Arch-Slave (Bulk Storage/Compute).

## 5. Wishlist (Future Integration)
*   **Nyxt Browser:** Investigation into [Nyxt](https://nyxt.atlas.engineer/) as the primary workstation browser (Lisp-powered, highly hackable, fits the "Second Skin" ethos).
*   **System Haptics & Audio:** Declarative soundscapes.
*   **AI Infusion:** "Self-aware" hooks for LLM-driven ricing and optimization.

## 6. Success Metrics
*   **System Rebuild (Offline):** Rebuilding the NixOS configuration from a cached local flake takes < 10 seconds.
*   **Terminal Performance:** Kitty terminal launch time (UI visible) takes < 50 ms. Shell readiness (prompt interactive) takes < 100 ms.
*   **Impermanence Security:** Secrets audit tool returns 0 plain-text keys in the repository.

## 7. Risks & Mitigations
*   **NVIDIA Wayland Instability:** Potential for flickering, explicit sync issues, and sleep corruption. Mitigated by explicit kernel parameters and environment variables detailed in `software.md`, and documenting known bugs explicitly.
*   **sops-nix Key Management:** Loss of master age key could cause total system lockout. Mitigated by secure backup to self-hosted Seafile and syncing to Oracle VPS (mass media remains on Arch slave).

## 8. Out of Scope (V1)
*   Multi-GPU passthrough configurations.
*   Support for non-NVIDIA GPUs.
*   Complex home-lab server hosting (Mandragora is strictly a workstation).

## 9. Implementation Roadmap
*   [ ] Flake structure setup (`flake.nix`, `hosts/`, `modules/`).
*   [ ] NVIDIA & Wayland base module.
*   [ ] Dynamic Theming Engine (Wallpaper-to-Home-Manager pipeline).
*   [ ] Home Manager integration (linking existing dots).
*   [ ] Audit subsystem (Disk/Network diff scripts).
