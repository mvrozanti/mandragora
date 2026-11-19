#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${MANDRAGORA_REPO:-https://github.com/mvrozanti/mandragora.git}"
REPO_DIR=/etc/nixos/mandragora
WORK_BRANCH="${MANDRAGORA_WORK_BRANCH:-work}"
LOG="$HOME/Library/Logs/mandragora-bootstrap.log"
NIX_PROFILE=/nix/var/nix/profiles/default

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

step() { printf '\n[%s] %s\n' "$1" "$2"; }
die() {
  printf 'error: %s\n' "$*" >&2
  printf 'full log: %s\n' "$LOG" >&2
  exit 1
}

step 1/6 preflight
[ "$(uname -s)" = Darwin ] || die "this bootstrap is for macOS"
[ "$(uname -m)" = arm64 ] || die "mandragora-macos targets Apple Silicon; this Mac reports $(uname -m)"
id -Gn | tr ' ' '\n' | grep -qx admin ||
  die "account '$USER' is not an administrator. Installing Nix needs admin once (it creates the /nix volume): get temporary admin rights from IT or the Self Service / Privileges app, then re-run."
echo "    macOS $(sw_vers -productVersion), user $USER"
echo "    repo $REPO_DIR on branch $WORK_BRANCH, personal slice: ${MANDRAGORA_PERSONAL:-0}"
echo "    log $LOG"
echo "    sudo will ask for your password"
sudo -v

step 2/6 nix
if [ -x "$NIX_PROFILE/bin/nix" ] || [ -x /run/current-system/sw/bin/nix ]; then
  echo "    already installed"
else
  curl -sSfL https://install.lix.systems/lix | sh -s -- install --no-confirm
fi
if [ -r "$NIX_PROFILE/etc/profile.d/nix-daemon.sh" ]; then
  set +u
  . "$NIX_PROFILE/etc/profile.d/nix-daemon.sh"
  set -u
fi
export PATH="/run/current-system/sw/bin:$NIX_PROFILE/bin:$PATH"
command -v nix >/dev/null || die "nix is not on PATH after install; open a new terminal and re-run"
NIX=(nix --extra-experimental-features "nix-command flakes")

step 3/6 homebrew
if [ -x /opt/homebrew/bin/brew ]; then
  echo "    already installed"
else
  sudo -v
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

step 4/6 repo
GIT="$("${NIX[@]}" build --no-link --print-out-paths nixpkgs#git | tail -1)/bin/git"
if [ -d "$REPO_DIR/.git" ]; then
  echo "    keeping the existing checkout (merge upstream later with 'nrs')"
else
  sudo mkdir -p "$REPO_DIR"
  sudo chown "$USER:staff" "$REPO_DIR"
  "$GIT" clone "$REPO_URL" "$REPO_DIR"
fi
if ! "$GIT" -C "$REPO_DIR" rev-parse --verify --quiet "$WORK_BRANCH" >/dev/null; then
  echo "    creating the local '$WORK_BRANCH' branch (never pushed)"
  "$GIT" -C "$REPO_DIR" checkout -b "$WORK_BRANCH"
elif [ "$("$GIT" -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null)" != "$WORK_BRANCH" ]; then
  "$GIT" -C "$REPO_DIR" checkout "$WORK_BRANCH"
fi
"$GIT" -C "$REPO_DIR" config merge.autoStash true
"$GIT" -C "$REPO_DIR" config branch."$WORK_BRANCH".pushRemote no_push

step 5/6 "build and switch mandragora-macos"
system=$(SUDO_USER="$USER" "${NIX[@]}" build --no-link --print-out-paths --impure \
  "$REPO_DIR#darwinConfigurations.mandragora-macos.system" | tail -1)
[ -x "$system/sw/bin/darwin-rebuild" ] || die "the build did not produce darwin-rebuild"

switch_log=$(mktemp -t mandragora-switch)
switch() {
  set +e
  sudo --preserve-env=MANDRAGORA_PERSONAL,PATH "$system/sw/bin/darwin-rebuild" switch \
    --flake "$REPO_DIR#mandragora-macos" --impure 2>&1 | tee "$switch_log"
  local rc=${PIPESTATUS[0]}
  set -e
  return "$rc"
}

if ! switch; then
  grep -q "Unexpected files in /etc" "$switch_log" || die "darwin-rebuild switch failed"
  moved=()
  while IFS= read -r f; do
    [ -e "$f.before-nix-darwin" ] && die "$f.before-nix-darwin already exists; compare it with $f, keep one, re-run"
    sudo mv "$f" "$f.before-nix-darwin"
    moved+=("$f")
  done < <(sed -n 's|^  \(/etc/[^ ]*\)$|\1|p' "$switch_log")
  [ ${#moved[@]} -gt 0 ] || die "nix-darwin refused /etc files but none could be parsed from $switch_log"
  printf '\n    NOTICE: these files had content nix-darwin does not recognise (likely set by IT).\n'
  printf '    They were renamed, not deleted. Diff them and port anything that matters (proxies, certs):\n'
  for f in "${moved[@]}"; do printf '      %s -> %s.before-nix-darwin\n' "$f" "$f"; done
  switch || die "darwin-rebuild switch failed after moving the files aside"
fi

step 6/6 verify
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
fail=0
for c in darwin-rebuild mandragora-macos-switch claude rtk nvim tmux yazi kitty; do
  if command -v "$c" >/dev/null; then echo "    ok       $c"; else
    echo "    MISSING  $c"
    fail=1
  fi
done
if printf mandragora | wl-copy && [ "$(wl-paste)" = mandragora ]; then
  echo "    ok       wl-copy/wl-paste -> macOS clipboard"
else
  echo "    BROKEN   clipboard shims"
  fail=1
fi
head_bin=$(zsh -lic 'command -v head' 2>/dev/null | tail -1)
case "$head_bin" in
  /usr/bin/*)
    echo "    WARN     login shells find BSD $head_bin before GNU coreutils"
    fail=1
    ;;
  *) echo "    ok       GNU userland first on PATH ($head_bin)" ;;
esac

if [ "$fail" -ne 0 ]; then
  die "bootstrap finished with problems above; send $LOG"
fi
echo
echo "mandragora-macos is ready. Open kitty (Spotlight: kitty). Later updates: nrs"
