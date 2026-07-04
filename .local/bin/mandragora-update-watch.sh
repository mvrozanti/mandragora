#!/usr/bin/env bash
set -uo pipefail

FLAKE="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
HOST="${MANDRAGORA_HOST:-mandragora-desktop}"
STATUSDIR="${MANDRAGORA_STATUS_DIR:-/persistent/mandragora-update}"
NOTIFY="${MANDRAGORA_NOTIFY_BIN:-telegram-notify}"
RUNBASE="${XDG_RUNTIME_DIR:-/tmp}"
WT="$RUNBASE/mandragora-update-watch-wt"

mkdir -p "$STATUSDIR"
LOG="$STATUSDIR/watch-build.log"

cleanup() {
  git -C "$FLAKE" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
  git -C "$FLAKE" worktree prune 2>/dev/null || true
}
trap cleanup EXIT

git -C "$FLAKE" fetch origin >/dev/null 2>&1 || true
MASTER=$(git -C "$FLAKE" rev-parse refs/heads/master)
rm -rf "$WT"
git -C "$FLAKE" worktree prune 2>/dev/null || true
git -C "$FLAKE" worktree add --detach "$WT" "$MASTER" >/dev/null 2>&1 || exit 0
cd "$WT" || exit 0

nix flake update >/dev/null 2>&1 || { echo "flake update failed" >"$LOG"; exit 0; }

sed -i 's/\bsilver-searcher\b/silver-searcher-ng/g' \
  nix/modules/shared/home-cli.nix nix/modules/user/home.nix 2>/dev/null || true
printf '_:\n\n{\n  nixpkgs.overlays = [ ];\n}\n' > nix/modules/shared/overlays.nix

rev=$(nix flake metadata "$WT" --json 2>/dev/null \
  | grep -oE '"nixpkgs"[^}]*"rev":"[0-9a-f]{40}"' | grep -oE '[0-9a-f]{40}' | head -1)

if nix build ".#nixosConfigurations.${HOST}.config.system.build.toplevel" \
     --no-link --keep-going >"$LOG" 2>&1; then
  was_blocked=1
  [ -f "$STATUSDIR/viable.txt" ] && was_blocked=0
  echo "viable $(date -Is) nixpkgs ${rev}" > "$STATUSDIR/viable.txt"
  rm -f "$STATUSDIR/blocked.txt" 2>/dev/null || true
  if [ "$was_blocked" -eq 1 ]; then
    "$NOTIFY" "Mandragora update is viable again — the nixpkgs window cleared (nixpkgs ${rev:0:12}). It builds clean. Run: mandragora-update"
  fi
else
  reason=$(grep -m1 -iE "of_gpio|bootloader cannot find|has been removed|marked as insecure|error: builder" "$LOG" \
    | sed -E 's/^\s+//; s/^> //' | cut -c1-120)
  echo "blocked $(date -Is) nixpkgs ${rev}: ${reason:-see watch-build.log}" > "$STATUSDIR/blocked.txt"
  rm -f "$STATUSDIR/viable.txt" 2>/dev/null || true
fi
exit 0
