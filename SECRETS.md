# Mandragora Secrets: The Sovereign Vault

This document defines the technical strategy for keeping secrets out of version control while maintaining a fully declarative Nix system.

## 1. Zero-Secret Mandate
No plain-text password, API key, or private key shall exist in any Git branch. 

## 2. Tooling: `sops-nix`
Mandragora uses `sops-nix` for its native integration with the NixOS module system.
- **Encryption:** AES-256 via `sops`.
- **Key Management:** Age keys (for local machines) and ed25519 SSH keys (for the Oracle VPS/Slave).
- **Storage:** Encrypted `.yaml` or `.json` files in the `secrets/` directory.

## 3. Secret Categories

| Category          | Encryption Key        | Implementation Logic                   |
|-------------------|-----------------------|----------------------------------------|
| **Wi-Fi / Network**| Host SSH Key          | `sops.secrets."wireless.env"`          |
| **Seafile Creds** | User Age Key          | `sops.secrets."seafile/token"`         |
| **Oracle SSH**    | Master Age Key        | `sops.secrets."ssh/oracle-vps"`       |

- This directory is encrypted with a key that is **NEVER** present on the Main profile's accessible filesystem.

## 5. Agent Instructions for Secrets
- **NEVER** ask for a password in plain text.
- **NEVER** propose a Nix module that contains a string like `password = "123456";`.
- **ALWAYS** check for the existence of a corresponding `sops.secrets` entry before configuring a service that requires authentication.

## 6. Key Recovery (The "Lifeboat")
A master `age` key must be stored in physical "Cold Storage" (e.g., a paper backup or a dedicated USB in a safe) to prevent total lockout if all machines are lost.
