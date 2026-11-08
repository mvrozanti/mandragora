#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
cage — run a heavy command inside the memory-capped heavy.slice cgroup.

Usage: cage <command> [args...]

Runs the command in heavy.slice (MemoryHigh=16G soft throttle,
MemoryMax=20G hard kill).
If it blows the cap it dies alone; the compositor, tmux, claude, and the
rest of the session are never touched. Use for builds, training runs,
data crunching, anything you know is hungry. All cage'd jobs share the
one slice ceiling, so two heavy runs at once still can't exceed it.
Outside the user manager (a system service, a cron job) there is no user
bus to create the scope on, so the command runs uncaged with a warning.
EOF
  exit 0
fi

uid=$(id -u)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"
read -r cgroup < /proc/self/cgroup
if [[ $cgroup != "0::/user.slice/user-$uid.slice/user@$uid.service/"* ]]; then
  echo "cage: not inside the user manager of uid $uid; running uncaged" >&2
  exec "$@"
fi

exec systemd-run \
  --user \
  --slice=heavy.slice \
  --scope \
  --collect \
  --quiet \
  -- "$@"
