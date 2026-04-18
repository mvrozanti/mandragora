# Mandragora Open Decisions

Every unresolved question that blocks the build. Answered = moved to [`DECISIONS.md`](../DECISIONS.md).

---

## 1. `hardware-configuration.nix`

**Problem:** Contains disk UUIDs and detected kernel modules. Doesn't exist until install.

| Approach | How |
|----------|-----|
| **Commit at install** | `nixos-generate-config` produces it on the live USB, `git add` it. |
| **Generate in flake** | Flake reads from target disk at build time. Complex, fragile. |

**Recommendation:** Commit at install. Standard NixOS workflow.

---

## 2. Seafile Server on arch-slave

**Problem:** Seafile needs a server component running somewhere.

**Recommendation:** Defer. Set up Seafile server on arch-slave after mandragora-desktop boots. Configure the client module now, point to placeholder URL, update when server is ready.
