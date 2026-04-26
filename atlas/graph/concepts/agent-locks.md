---
type: concept
tags: [concept, agents, workflow]
---

# Agent locks

`mandragora-lock` is the cooperation protocol when multiple AI agents (or humans) edit the repo at once. Two phases:

- **edit** — path-disjoint claims; agents may work in parallel as long as their declared paths don't overlap.
- **commit** — exclusive; claimed by [[../scripts/mandragora-switch]] for the duration of `nixos-rebuild`.

Lock dir is RAM-backed (`/dev/shm/mandragora-locks/`), serialized by `flock`, and prunes dead PIDs automatically. Tool-call agents (no long-lived PID) rely on TTL, not auto-prune.

## Touched by

- [[../scripts/mandragora-lock]] — the tool itself
- [[../scripts/mandragora-switch]] — claims `phase=commit` exclusively
- [[../modules/user/home]] — wraps both into the user PATH

See: [[../../non-negotiables]]
