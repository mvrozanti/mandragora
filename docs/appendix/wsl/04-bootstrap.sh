#!/usr/bin/env bash
# Run inside NixOS-WSL (`wsl -d NixOS bash 04-bootstrap.sh`).
# Clones mandragora and switches to the mandragora-wsl host.

set -eo pipefail

if [ -f /etc/profile ]; then set +u; . /etc/profile; set -u; fi
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:$PATH"
set -u

REPO_URL="${MANDRAGORA_REPO:-https://github.com/mvrozanti/mandragora.git}"
REPO_DIR="${MANDRAGORA_DIR:-/etc/nixos/mandragora}"
REPLACE_POLICY="${MANDRAGORA_REPLACE:-prompt}"
LOG_DIR="${MANDRAGORA_LOG_DIR:-}"

log_to() {
    local name="$1"
    if [ -n "$LOG_DIR" ] && [ -d "$LOG_DIR" ]; then
        printf '%s/%s' "$LOG_DIR" "$name"
    else
        printf '/dev/null'
    fi
}

confirm_replace() {
    local what="$1"
    case "$REPLACE_POLICY" in
        all|yes)  echo "    '$what' exists — replacing (MANDRAGORA_REPLACE=$REPLACE_POLICY)"; return 0 ;;
        none|no)  echo "    '$what' exists — keeping  (MANDRAGORA_REPLACE=$REPLACE_POLICY)"; return 1 ;;
    esac
    local tty=/dev/tty
    if [ ! -r "$tty" ] || [ ! -w "$tty" ]; then
        echo "    '$what' exists and no TTY available — keeping (default No)"
        return 1
    fi
    local r
    while true; do
        printf "    '%s' already exists. Replace? [Y]es / [N]o / [A]ll / N[o]ne: " "$what" >"$tty"
        IFS= read -r r <"$tty"
        case "${r,,}" in
            y|yes)  return 0 ;;
            n|no)   return 1 ;;
            a|all)  REPLACE_POLICY=all;  return 0 ;;
            o|none) REPLACE_POLICY=none; return 1 ;;
        esac
    done
}

echo '[1/3] ensure git is available'
if ! command -v git >/dev/null 2>&1; then
    nix-env -iA nixos.git
fi

echo '[2/3] obtain mandragora repo'
WORK_BRANCH="${MANDRAGORA_WORK_BRANCH:-work}"
if [ -d "$REPO_DIR/.git" ]; then
    if confirm_replace "$REPO_DIR"; then
        sudo rm -rf "$REPO_DIR"
        sudo mkdir -p "$(dirname "$REPO_DIR")"
        sudo chown "$USER:users" "$(dirname "$REPO_DIR")"
        git clone "$REPO_URL" "$REPO_DIR"
    else
        echo "    keeping existing checkout (no pull -- merge upstream via 'nrs' on demand)"
    fi
else
    sudo mkdir -p "$(dirname "$REPO_DIR")"
    sudo chown "$USER:users" "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
fi

if ! git -C "$REPO_DIR" rev-parse --verify --quiet "$WORK_BRANCH" >/dev/null; then
    echo "    creating local '$WORK_BRANCH' branch (never pushed)"
    git -C "$REPO_DIR" checkout -b "$WORK_BRANCH"
elif [ "$(git -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null)" != "$WORK_BRANCH" ]; then
    git -C "$REPO_DIR" checkout "$WORK_BRANCH"
fi
git -C "$REPO_DIR" config merge.autoStash true
git -C "$REPO_DIR" config branch."$WORK_BRANCH".pushRemote no_push

echo '[3/3] build mandragora-wsl host'
git -C "$REPO_DIR" add -A
rebuild_log="$(log_to nixos-rebuild.log)"
echo "    rebuild log -> $rebuild_log"
set +e
sudo --preserve-env=MANDRAGORA_PERSONAL nixos-rebuild switch \
    --flake "$REPO_DIR#mandragora-wsl" \
    --impure 2>&1 | tee -a "$rebuild_log"
rebuild_rc=${PIPESTATUS[0]}
set -e
if [ "$rebuild_rc" -ne 0 ]; then
    echo "nixos-rebuild switch exited $rebuild_rc -- see $rebuild_log" >&2
    exit "$rebuild_rc"
fi

active_host="$(cat /etc/hostname 2>/dev/null | tr -d '[:space:]')"
if [ "$active_host" != "mandragora-wsl" ]; then
    echo "bootstrap incomplete: /etc/hostname is '$active_host', expected 'mandragora-wsl'" >&2
    exit 1
fi

echo "active generation: $(nixos-version)"
echo 'mandragora-wsl bootstrap complete.'
