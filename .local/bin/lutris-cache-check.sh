#!/usr/bin/env bash
set -euo pipefail

FLAKE_LOCK=/etc/nixos/mandragora/flake.lock

if [[ ! -r "$FLAKE_LOCK" ]]; then
  exit 0
fi

NP_NODE=$(jq -r '.nodes.root.inputs.nixpkgs' "$FLAKE_LOCK")
REV=$(jq -r ".nodes.\"$NP_NODE\".locked.rev" "$FLAKE_LOCK")

eval_path() {
  local attr="$1"
  nix --extra-experimental-features 'nix-command flakes' eval --raw --impure --expr \
    "(import (builtins.fetchTarball \"https://github.com/nixos/nixpkgs/archive/$REV.tar.gz\") { system = \"x86_64-linux\"; config.allowUnfree = true; }).$attr.outPath"
}

X64_PATH=$(eval_path "openldap")
I686_PATH=$(eval_path "pkgsi686Linux.openldap")

X64_HASH=$(basename "$X64_PATH" | cut -d- -f1)
I686_HASH=$(basename "$I686_PATH" | cut -d- -f1)

probe() {
  curl -s -o /dev/null -w "%{http_code}" "https://cache.nixos.org/$1.narinfo"
}

x64_code=$(probe "$X64_HASH")
i686_code=$(probe "$I686_HASH")

echo "rev=$REV x64=$X64_PATH ($x64_code) i686=$I686_PATH ($i686_code)"

if [[ "$x64_code" == "200" && "$i686_code" == "200" ]]; then
  notify-send -u critical -t 0 \
    "Lutris install ready" \
    "openldap cached on cache.nixos.org for nixpkgs $REV (x86_64 + i686). Add 'lutris' to home.packages and switch."
  systemctl --user disable --now lutris-cache-check.timer || true
fi
