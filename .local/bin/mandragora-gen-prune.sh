#!/usr/bin/env bash
set -uo pipefail
PROFILE=/nix/var/nix/profiles/system

usage() {
  echo "usage: mandragora-gen-prune <generation-number>... | <N>d" >&2
  echo "  deletes only numbered system generations, or those older than N days." >&2
  exit 2
}

[ "$#" -ge 1 ] || usage

if [ "$#" -eq 1 ] && [[ "$1" =~ ^[0-9]+d$ ]]; then
  exec nix-env -p "$PROFILE" --delete-generations "$1"
fi

for g in "$@"; do
  [[ "$g" =~ ^[0-9]+$ ]] || usage
done
exec nix-env -p "$PROFILE" --delete-generations "$@"
