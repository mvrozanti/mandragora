#!/usr/bin/env bash
real="$REAL_NIXOS_REBUILD"
repo_git=$(realpath -e "$MANDRAGORA_REPO_DIR/.git")
args=("$@")

refuse() {
  {
    printf 'nixos-rebuild guard REFUSED: %s\n' "$1"
    shift
    for line in "$@"; do printf '  %s\n' "$line"; done
    printf 'Only switch/boot/test/build/dry-build of one local mandragora checkout, with no\n'
    printf 'other flags, is allowed without a password. Everything else runs as root and so\n'
    printf 'needs the operator password:\n'
    printf '  sudo %s %s\n' "$real" "${args[*]}"
  } | sed 's/^/error: /' >&2
  exit 3
}

help_only=1
for a in "${args[@]}"; do
  case "$a" in -h | --help | --version) ;; *) help_only=0 ;; esac
done
[ "${#args[@]}" -gt 0 ] && [ "$help_only" -eq 1 ] && exec "$real" "$@"

actions=()
flakes=()
extra=()
i=0
while [ "$i" -lt "${#args[@]}" ]; do
  a="${args[$i]}"
  case "$a" in
    switch | boot | test | build | dry-build) actions+=("$a") ;;
    --flake=* | -F=*) flakes+=("${a#*=}") ;;
    --flake | -F)
      i=$((i + 1))
      flakes+=("${args[$i]:-}")
      ;;
    -F?*) flakes+=("${a#-F}") ;;
    *) extra+=("$a") ;;
  esac
  i=$((i + 1))
done

[ "${#actions[@]}" -eq 1 ] || refuse "expected exactly one of switch/boot/test/build/dry-build; got: ${actions[*]:-none}"
[ "${#flakes[@]}" -eq 1 ] || refuse "expected exactly one --flake <checkout>#<host>; got ${#flakes[@]}"
[ "${#extra[@]}" -eq 0 ] || refuse "no other flags or arguments are allowed here; got: ${extra[*]}"

action="${actions[0]}"
flake="${flakes[0]}"
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

activating=0
case "$action" in switch | boot | test) activating=1 ;; esac

if [ "$activating" -eq 1 ]; then
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
fi

pinned="git+file://$top?rev=$new"

printf 'nixos-rebuild guard: %s %s (%s)\n' "$action" "${new:0:12}" "$(as_owner git -C "$dir" log -1 --format=%s "$new")" >&2

[ "$activating" -eq 1 ] || exec "$real" "$action" --flake "$pinned$attr"

config="${attr#\#}"
[ -n "$config" ] || config=$(uname -n)
owner_home=$(getent passwd "$owner" | cut -d: -f6)
gcroot=$(as_owner mktemp -d -t nixos-rebuild-guard.XXXXXX)
trap 'rm -rf "$gcroot"' EXIT

toplevel=$(as_owner env -u XDG_CACHE_HOME -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME HOME="$owner_home" \
  nix build --out-link "$gcroot/result" --print-out-paths \
  "$pinned#nixosConfigurations.\"$config\".config.system.build.toplevel")
printf 'nixos-rebuild guard: built %s as %s; activating it as root\n' "$toplevel" "$owner" >&2

rc=0
"$real" "$action" --no-reexec --store-path "$toplevel" || rc=$?
exit "$rc"
