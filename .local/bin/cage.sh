#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
cage — run a heavy command inside the memory-capped heavy.slice cgroup.

Usage: cage <command> [args...]

Runs the command in heavy.slice (MemoryHigh=16G soft throttle,
MemoryMax=20G hard kill, ManagedOOMMemoryPressure=kill; dies before the spine).
If it blows the cap it dies alone; the compositor, tmux, claude, and the
rest of the session are never touched. Use for builds, training runs,
data crunching, anything you know is hungry. All cage'd jobs share the
one slice ceiling, so two heavy runs at once still can't exceed it.
EOF
  exit 0
fi

exec systemd-run \
  --user \
  --slice=heavy.slice \
  --scope \
  --collect \
  --quiet \
  -- "$@"
