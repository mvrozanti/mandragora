#!/usr/bin/env bash
real="$REAL_NIXOS_REBUILD"
repo_git=$(realpath -e "$MANDRAGORA_REPO_DIR/.git")
args=("$@")

refuse() {
  {
    printf 'nixos-rebuild guard REFUSED: %s\n' "$1"
    shift
    for line in "$@"; do printf '  %s\n' "$line"; done
    printf 'The running system only moves forward: every activation is a clean commit that\n'
    printf 'contains everything the running and boot generations were built from.\n'
    printf 'Overriding discards that work and needs the operator password:\n'
    printf '  sudo %s %s\n' "$real" "${args[*]}"
  } | sed 's/^/error: /' >&2
  exit 3
}

activating=0
rollback=0
nonflake=0
flake=""
flake_idx=-1
i=0
while [ "$i" -lt "${#args[@]}" ]; do
  a="${args[$i]}"
  case "$a" in
    switch | boot | test) activating=1 ;;
    --rollback) rollback=1 ;;
    --no-flake | --file | --file=* | -f | --attr | --attr=* | -A | -I) nonflake=1 ;;
    --flake)
      flake_idx=$((i + 1))
      flake="${args[$flake_idx]:-}"
      i=$((i + 1))
      ;;
    --flake=*)
      flake_idx=$i
      flake="${a#--flake=}"
      ;;
  esac
  i=$((i + 1))
done

[ "$activating" -eq 1 ] || exec "$real" "$@"

[ "$rollback" -eq 0 ] || refuse "--rollback activates an older generation."
[ "$nonflake" -eq 0 ] || refuse "only a flake build from a checkout of the mandragora repo can be activated."
[ -n "$flake" ] || refuse "no --flake given; pass --flake <checkout>#<host>."

ref="${flake%%#*}"
attr=""
case "$flake" in *'#'*) attr="#${flake#*#}" ;; esac
case "$ref" in
  /* | . | ./* | .. | ../*) ;;
  *) refuse "'$ref' is not a local checkout; build from a worktree of $MANDRAGORA_REPO_DIR." ;;
esac

dir=$(realpath -e "$ref") || refuse "'$ref' does not exist."
owner=$(stat -c %U "$dir")

as_owner() {
  if [ "$(id -u)" -eq 0 ] && [ "$owner" != root ]; then
    runuser -u "$owner" -- "$@"
  else
    "$@"
  fi
}

top=$(as_owner git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || refuse "'$dir' is not a git checkout."
[ "$(realpath -e "$top")" = "$dir" ] || refuse "'$dir' is not the root of its checkout ($top)."
common=$(as_owner git -C "$dir" rev-parse --path-format=absolute --git-common-dir)
[ "$(realpath -e "$common")" = "$repo_git" ] || refuse "'$dir' is not a checkout of $MANDRAGORA_REPO_DIR."

dirty=$(as_owner git -C "$dir" status --porcelain --untracked-files=no)
if [ -n "$dirty" ]; then
  mapfile -t dirty_lines <<<"$dirty"
  refuse "'$dir' has uncommitted changes; commit them first (a WIP commit in your worktree is fine)." "${dirty_lines[@]}"
fi

new=$(as_owner git -C "$dir" rev-parse HEAD)

for gen in /run/current-system /nix/var/nix/profiles/system; do
  live=$(cat "$gen/git-revision" 2>/dev/null || true)
  case "$live" in
    "" | dirty | *-dirty)
      refuse "$gen was built from uncommitted changes (${live:-no revision recorded}); nothing can prove a new build keeps them." \
        "Whoever built it must commit and land it with mandragora-switch."
      ;;
  esac
  as_owner git -C "$dir" cat-file -e "$live^{commit}" 2>/dev/null \
    || refuse "$gen was built from $live, which is not in this repo."
  mapfile -t missing < <(as_owner git -C "$dir" cherry "$new" "$live" | sed -n 's/^+ //p')
  if [ "${#missing[@]}" -gt 0 ]; then
    mapfile -t lost < <(as_owner git -C "$dir" log --no-walk=unsorted --format='%h %s' "${missing[@]}")
    mapfile -t holders < <(as_owner git -C "$dir" branch --all --contains "$live" --format='%(refname:short)')
    refuse "$gen runs commits that ${new:0:12} does not contain:" "${lost[@]}" \
      "held by: ${holders[*]:-no branch (detached)}" \
      "Land them (or rebase onto them) first; the build must descend from what is running."
  fi
done

if [ "$flake_idx" -eq -1 ]; then
  refuse "internal: --flake position not found."
fi
pinned="git+file://$top?rev=$new$attr"
case "${args[$flake_idx]}" in
  --flake=*) args[flake_idx]="--flake=$pinned" ;;
  *) args[flake_idx]="$pinned" ;;
esac

printf 'nixos-rebuild guard: activating %s (%s)\n' "${new:0:12}" "$(as_owner git -C "$dir" log -1 --format=%s "$new")" >&2
exec "$real" "${args[@]}"
