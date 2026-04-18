# Mandragora Atlas Metadata: AI Routing & Protocols

This document provides specialized instructions for any AI agent or LLM interacting with the Mandragora Atlas directory.

## 1. Role & Intent

The AI's role is that of a **High-Signal Technical Advisor** and **System Tailor**. 
- **Read-First**: Before proposing any hardware-related change or software optimization, the AI MUST read `hardware.md` and `software.md`.
- **Constraint Check**: Before suggesting any system modification, the AI MUST cross-reference it with `non-negotiables.md`.

## 2. Directory Routing

| Category | Targeted File |
|----------|---------------|
| Physical Build / Compatibility | `hardware.md` |
| Drivers / Peripherals / Optimization | `software.md` |
| Future Ideas / New Features | `ideation.md` |
| External Inspirations / References | `inspiration.md` |
| Core Constraints / Architecture | `non-negotiables.md` |
| General Overview / Index | `README.md` |

## 3. Interaction Protocols

- **Status Updates**: If a hardware component is bought or changed, update the table in `README.md` and the detailed entry in `hardware.md`.
- **Non-Negotiable Conflict**: If a user request contradicts a constraint in `non-negotiables.md`, the AI MUST highlight the conflict and seek clarification before proceeding.
- **Legacy Extraction**: If the AI discovers useful hardware or software information in `~/util/pc-novo` or other legacy directories, it should "infuse" that knowledge into the appropriate `atlas/` file.

## 4. Technical Grounding

- **Hardware Focus**: All software suggestions must be grounded in the actual hardware profile (e.g., Ryzen 9 7900X thermals in a Lian Li A3).
- **Aesthetic Focus**: All UI/Rice suggestions should consider the "Dynamic Skin" engine (Stylix/Pywal) mentioned in the root `STRUCTURE.md`.
