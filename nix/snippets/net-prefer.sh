#!/usr/bin/env bash
set -eu

RUNDIR=/run/net-failover
mode="${1:-}"

case "$mode" in
  lan|wifi|auto)
    mkdir -p "$RUNDIR"
    printf '%s\n' "$mode" > "$RUNDIR/mode"
    ;;
  *)
    echo "usage: net-prefer lan|wifi|auto" >&2
    exit 1
    ;;
esac
