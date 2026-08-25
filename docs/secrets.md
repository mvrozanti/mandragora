# Mandragora Secrets: The Sovereign Vault

This document defines the technical strategy for keeping secrets out of version control while maintaining a fully declarative Nix system.

## 1. Zero-Secret Mandate
No plain-text password, API key, or private key shall exist in any Git branch. 

## 2. Tooling: `sops-nix`
Mandragora uses `sops-nix` for its native integration with the NixOS module system.
- **Encryption:** AES-256 via `sops`, with key wrapping by `age`.
- **Storage:** Encrypted `.yaml` files under `secrets/`, committed to the
  public repo. Ciphertext is safe to publish; the identity is not.

## 3. Key Model
There is exactly **one** recipient. `.sops.yaml` declares a single age
public key (`&main`) and a single creation rule, `path_regex:
secrets/.*\.yaml$` — so any `.yaml` at any depth under `secrets/` is
encrypted to that one identity, with no per-file configuration.

| Item | Value |
|---|---|
| Recipient | the `&main` age public key in `.sops.yaml` |
| Private identity | `/persistent/secrets/keys.txt` (root, `0600`, desktop only) |
| Nix wiring | `nix/modules/core/secrets.nix` (`sops.age.keyFile`) |
| Reference syntax | `config.sops.secrets."<path>".path` |
| Edit wrapper | `.local/bin/sss.sh` (wraps `sudo sops`) |

Secrets are slash-namespaced (`user/password`, `github/personal_access_token`,
`perception/twitch_client_secret`, …). Run `sops filestatus` to confirm a
file is encrypted without decrypting it.

**No host other than `mandragora-desktop` holds a decryption identity.**
There are no SSH-key-derived recipients and no per-host age keys. Adding a
host means adding its public key to `.sops.yaml` and re-encrypting — note
that `docs/install/bootstrap-age-key.sh` *overwrites* `.sops.yaml`
wholesale and would drop any recipient added after first install.

## 4. VPS Runtime Secrets
`mandragora-vps` is not a NixOS host and has no age identity, so
`sops.secrets` does not reach it. Its docker-compose stacks read plain
`.env` files, which for a long time existed **only** on that instance's
boot volume — unrecoverable if the volume were ever lost.

Those files are now mirrored into `secrets/vps/<name>.yaml`, one encrypted
file per runtime file, described by
[`../nix/hosts/mandragora-vps/env-manifest.json`](../nix/hosts/mandragora-vps/env-manifest.json)
and moved by
[`../nix/hosts/mandragora-vps/sync-env.sh`](../nix/hosts/mandragora-vps/sync-env.sh):

```
sync-env.sh --pull   --all    # VPS  -> secrets/vps/*.yaml  (capture)
sync-env.sh --push   <name>   # secrets/vps/*.yaml -> VPS   (restore)
sync-env.sh --verify --all    # compare both sides, revealing nothing
```

The desktop is always the one that decrypts; the VPS only ever receives a
rendered file, restored to the uid/gid/mode recorded in the manifest.
Plaintext is streamed through a pipe in both directions and never written
to local disk. `--verify` compares key names and per-value digests for
dotenv entries, and a whole-content digest for binary entries, so it can
prove the two sides agree without printing a secret.

Note that `--pull`/`--push` normalises dotenv whitespace: values, keys and
comments round-trip byte-exactly, but blank lines are dropped. Three files
(`basilica`, `drive-crypto-stox`, `seafile`) therefore differ cosmetically
from their VPS copies while being functionally identical.

`deploy-stacks.sh` deliberately never sends or deletes remote `.env`
files, so the two drivers do not interfere.

## 5. Agent Instructions for Secrets
- **NEVER** ask for a password in plain text.
- **NEVER** propose a Nix module that contains a string like `password = "123456";`.
- **ALWAYS** check for the existence of a corresponding `sops.secrets` entry before configuring a service that requires authentication.
- **NEVER** read, print, or log the contents of `secrets/`, or of any `.env` on `mandragora-vps`. Use `sync-env.sh --verify` to check them instead.

## 6. Key Recovery (The "Lifeboat")
A master `age` key must be stored in physical "Cold Storage" (e.g., a paper backup or a dedicated USB in a safe) to prevent total lockout if all machines are lost.

In addition to cold storage, the `age-key-backup` service (`nix/modules/core/backup.nix`) mirrors the key weekly to `mandragora-vps` at `/home/opc/backups/age-key/keys.txt` and verifies the copy — see [`docs/persistence.md`](persistence.md) §2–3 for the stream/verify mechanics and restore runbook.
