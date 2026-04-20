# Mandragora TODO: The Execution Roadmap

The authoritative build checklist is [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md).
This file tracks high-level phase status.

## Phase Status

| Phase | Status | Reference |
|-------|--------|-----------|
| Phase 1: Flake Skeleton | Not started | [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md#phase-1-flake-skeleton) |
| Phase 2: Core System | Not started | [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md#phase-2-core-system) |
| Phase 3: User & Desktop | Not started | [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md#phase-3-user--desktop) |
| Phase 4: Migration | Not started | [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md#phase-4-migration) |
| Phase 5: The Shadow | Not started | [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md#phase-5-the-shadow-shadow) |
| Phase 6: Sync & Polish | Not started | [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md#phase-6-sync--polish) |

All technical decisions are resolved in [`DECISIONS.md`](../DECISIONS.md).

---

## Open Hardware Issues

### RGB: RAM not detected by OpenRGB

**Diagnosis (2026-04-19):** Kingston Fury Beast DDR5 sticks have LEDs (confirmed visually) but OpenRGB cannot find them. `i2c_piix4` loads but creates zero adapters — the FCH SMBus for AM5/B650 is not enumerating.

**Next steps (in order):**
1. BIOS: `Advanced → AMD CBS → FCH Common Options → SMBUS → SMBus controller` — confirm enabled
2. If still missing after BIOS fix, add to `modules/core/boot.nix`:
   ```nix
   boot.extraModprobeConfig = "options i2c_piix4 force=1 force_addr=0x0b00";
   ```
3. Rebuild + reboot, then re-run `openrgb --list-devices` to verify RAM appears

### RGB: AIO fans not illuminated

**Diagnosis (2026-04-19):** MSI MAG Coreliquid A13 fans produce no light. The AIO has no USB HID device — it is ARGB-header-only. OpenRGB already detects `D_LED1 Bottom` and `D_LED2 Top` zones on the motherboard.

**Next step:** Physically connect the ARGB cable from the AIO fan hub to the `D_LED1` or `D_LED2` header on the B650M Aorus Elite AX. Once connected, OpenRGB controls it through the motherboard device — no extra config needed.
