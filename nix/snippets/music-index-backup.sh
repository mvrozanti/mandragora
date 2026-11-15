#!/usr/bin/env bash
: "${INDEX_RECIPIENT:?INDEX_RECIPIENT must be set}"
: "${INDEX_REMOTE:?INDEX_REMOTE must be set}"
: "${INDEX_REF:?INDEX_REF must be set}"
: "${INDEX_ANCHOR:?INDEX_ANCHOR must be set}"

state="${XDG_STATE_HOME:-$HOME/.local/state}/music-index-backup"
mkdir -p "$state"

index=$(mpc -f '%file%\t[%artist% - %title%]|[%file%]' listall \
  | awk -F'\t' '$1 !~ /^\./ { print $2 }' \
  | sed -E 's/\.(mp3|flac|opus|m4a|ogg|wav)$//I' \
  | LC_ALL=C sort -u)
[ -n "$index" ] || {
  echo "music-index-backup: mpd returned no tracks" >&2
  exit 1
}

digest=$(printf '%s\n' "$index" | sha256sum | cut -d' ' -f1)
if [ "$digest" = "$(cat "$state/digest" 2> /dev/null)" ]; then
  exit 0
fi

store=$(mktemp -d)
trap 'rm -rf "$store"' EXIT
git init -q --bare "$store"
export GIT_DIR="$store"
export GIT_AUTHOR_NAME=mandragora GIT_AUTHOR_EMAIL=mandragora@localhost
export GIT_COMMITTER_NAME=mandragora GIT_COMMITTER_EMAIL=mandragora@localhost

blob=$(printf '%s\n' "$index" | xz -9e | age -a -r "$INDEX_RECIPIENT" | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\t%s\n' "$blob" "$INDEX_ANCHOR" | git mktree)
git push -q --force "$INDEX_REMOTE" "$(git commit-tree "$tree" -m library):$INDEX_REF"

printf '%s\n' "$digest" > "$state/digest"
echo "music-index-backup: $(printf '%s\n' "$index" | wc -l) tracks mirrored to $INDEX_REF"
