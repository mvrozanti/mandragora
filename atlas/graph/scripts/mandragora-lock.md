---
type: script
tags: [script, workflow, agents]
path: .local/bin/mandragora-lock.sh
---

# mandragora-lock

Scope-based edit lock for multi-agent safety. Two phases: `edit` (cooperative, path-disjoint) and `commit` (exclusive, claimed by [[mandragora-switch]]).

Lock dir is `/dev/shm/mandragora-locks/` — RAM-backed so reboots clear stale state. Liveness-aware auto-prune on PID death.

Wrapped by: [[../modules/user/home]]
Touches: [[../concepts/agent-locks]], [[../concepts/declarative-supremacy]]
