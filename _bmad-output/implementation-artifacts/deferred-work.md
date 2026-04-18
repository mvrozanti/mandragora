# Deferred Work

## From Phase 5 — Shadow Profile review

- **stateVersion consistency**: Both `system.stateVersion` and `home.stateVersion` are set to `"24.05"` while the flake tracks `nixos-unstable`. This mirrors the mandragora-desktop pattern. Consider updating both when performing a full version bump.
- **LUKS password rotation path**: No mechanism exists in the Nix config to rotate the Shadow LUKS passphrase or add a recovery key. Operational documentation for this should be added.
- **Interactive passphrase in automated contexts**: `setup-shadow.sh` calls `cryptsetup luksFormat` which requires a TTY. Document that this script must be run interactively; add a note if unattended provisioning is ever needed.
- **Shadow theme**: `home-shadow.nix` ships with no theme. Theming deferred to KDE System Settings on first login. Future work: add `plasma-manager` as a flake input and configure declaratively.
