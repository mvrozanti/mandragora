# Mandragora Open Decisions

Every unresolved question that blocks the build. Answered = moved to [`DECISIONS.md`](../DECISIONS.md).

---

## 1. Impermanence Mechanism

**Problem:** We said "systemd service rebuilds root from last successful generation" but NixOS generations aren't Btrfs subvolumes.

| Approach | How it works | Risk |
|----------|-------------|------|
| **Shutdown-time seed** (`impermanence` module) | At shutdown, create a fresh root from a known-good seed, snapshot it. Next boot mounts the seed. | Shutdown must succeed. If it fails, next boot gets the dirty root. |
| **Boot-time rebuild** | Boot empty root, run `nixos-rebuild switch` to populate it. | Needs `/nix` mounted first. Service must run before `switch-root`. |

**Recommendation:** Use `impermanence` community module (shutdown-time). Battle-tested, documented.

---

## 2. `hardware-configuration.nix`

**Problem:** Contains disk UUIDs and detected kernel modules. Doesn't exist until install.

| Approach | How |
|----------|-----|
| **Commit at install** | `nixos-generate-config` produces it on the live USB, `git add` it. |
| **Generate in flake** | Flake reads from target disk at build time. Complex, fragile. |

**Recommendation:** Commit at install. Standard NixOS workflow.

---

## 3. Plymouth — Phase 2 Inclusion

**Problem:** Race condition with NVIDIA 570.x + Wayland SDDM. Untested.

**Recommendation:** Exclude Plymouth from Phase 2. Test Option D (`EnableAggressiveVblank`) on a running system. If it works, add Plymouth later.

---

## 5. Impermanence Failure Fallback

**Problem:** If the shutdown seed creation fails, next boot gets a corrupted root.

**Mitigation:** Keep the last known-good seed as an explicit fallback generation in systemd-boot. If the primary seed fails to boot, hold Shift and select "mandragora (fallback)" from the menu.

**Recommendation:** Explicit fallback generation, updated only after a successful seed creation.

---

## 6. Seafile Server on arch-slave

**Problem:** Seafile needs a server component running somewhere.

**Recommendation:** Defer. Set up Seafile server on arch-slave after mandragora-desktop boots. Configure the client module now, point to placeholder URL, update when server is ready.
