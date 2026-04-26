---
type: concept
tags: [concept, secrets, sops]
---

# Secrets (sops-nix)

Every secret in the system goes through sops-nix with age encryption (non-negotiable #4). The encrypted file at `secrets/secrets.yaml` is committed; the age key at `/persistent/secrets/keys.txt` is not.

Plain-text secrets in `.nix` files are forbidden. Agents never read `secrets/secrets.yaml`.

## Touched by

- [[../modules/core/secrets]] — sops-nix config + secret declarations
- [[../modules/core/globals]] — consumes the `hosts-oracle` template
- [[../modules/user/waybar]] — weather API key
- [[../modules/desktop/seafile]] — auth token (gated)
- [[../scripts/oracle-hosts-inject]] — renders the oracle hosts entry

See: [[impermanence]] (where the age key lives), [[../../non-negotiables]]
