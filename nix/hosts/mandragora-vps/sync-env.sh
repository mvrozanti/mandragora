#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
MANIFEST="$HERE/env-manifest.json"
SOPS_CONFIG="$REPO_ROOT/.sops.yaml"
SECRETS_SUBDIR="secrets/vps"
SECRETS_DIR="$REPO_ROOT/$SECRETS_SUBDIR"
AGE_KEY="${AGE_KEY:-/persistent/secrets/keys.txt}"
REMOTE="${REMOTE:-opc@mandragora-vps}"
REMOTE_ROOT="${REMOTE_ROOT:-/home/opc}"

MODE=""
DRY_RUN=0
ALL=0
NAMES=()

usage() {
  cat >&2 <<EOF
Usage: sync-env.sh (--pull | --push | --verify) [--dry-run] <name>... | --all

Moves mandragora-vps runtime secrets between the VPS and sops-encrypted
files under $SECRETS_SUBDIR/. Entries are declared in env-manifest.json.

Modes:
  --pull      VPS file -> $SECRETS_SUBDIR/<name>.yaml (encrypt). Overwrites
              the repo copy. Plaintext is streamed and never written to disk.
  --push      $SECRETS_SUBDIR/<name>.yaml -> VPS file (decrypt), restoring the
              manifest's uid/gid/mode. Plaintext never touches local disk.
  --verify    Compare repo copy against the VPS without revealing values:
              dotenv entries compare key names and per-value digests, binary
              entries compare a whole-content digest.

Options:
  --dry-run   Show targets; do not decrypt, transfer, or write.
  --all       Every entry in env-manifest.json.
  -h, --help  This help.

Environment:
  REMOTE        ssh target          default opc@mandragora-vps
  REMOTE_ROOT   remote slot root    default /home/opc
  AGE_KEY       sops age identity   default /persistent/secrets/keys.txt
EOF
}

log() { printf '→ %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERR: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --pull) MODE=pull; shift ;;
    --push) MODE=push; shift ;;
    --verify) MODE=verify; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --all) ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do NAMES+=("$1"); shift; done ;;
    -*) usage; die "unknown option: $1" ;;
    *) NAMES+=("$1"); shift ;;
  esac
done

[ -n "$MODE" ] || { usage; die "one of --pull, --push, --verify is required"; }
[ -f "$MANIFEST" ] || die "missing manifest: $MANIFEST"
command -v jq >/dev/null || die "jq is required"
command -v sops >/dev/null || die "sops is required"

if [ "$ALL" -eq 1 ]; then
  mapfile -t NAMES < <(jq -r '.entries[].name' "$MANIFEST")
fi
[ "${#NAMES[@]}" -gt 0 ] || { usage; die "no entries selected (pass names or --all)"; }

field() { jq -r --arg n "$1" '.entries[] | select(.name==$n) | .'"$2"'  // empty' "$MANIFEST"; }

decrypt_entry() {
  sudo -n SOPS_AGE_KEY_FILE="$AGE_KEY" sops --config "$SOPS_CONFIG" decrypt \
    --input-type yaml --output-type "$1" "$2"
}

digest_pairs() {
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"
    val="${line#*=}"
    printf '%s %s\n' "$key" "$(printf '%s' "$val" | sha256sum | cut -c1-16)"
  done | LC_ALL=C sort
}

pull_one() {
  local name="$1" remote type rel out tmp
  remote="$(field "$name" remote)"; type="$(field "$name" type)"
  [ -n "$remote" ] || { warn "skip '$name': not in manifest"; return 1; }
  rel="$SECRETS_SUBDIR/$name.yaml"
  out="$REPO_ROOT/$rel"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run pull $name  ($REMOTE:$REMOTE_ROOT/$remote → $rel, $type)"
    return 0
  fi

  mkdir -p "$SECRETS_DIR"
  tmp="$(mktemp "$out.XXXXXX")"
  if ssh -o BatchMode=yes "$REMOTE" "sudo -n cat '$REMOTE_ROOT/$remote'" \
      | sops --config "$SOPS_CONFIG" encrypt --input-type "$type" \
          --output-type yaml --filename-override "$rel" /dev/stdin > "$tmp"; then
    mv "$tmp" "$out"
    log "pull $name → $rel ($(wc -c < "$out") B ciphertext)"
  else
    rm -f "$tmp"
    warn "pull '$name' failed"
    return 1
  fi
}

push_one() {
  local name="$1" remote type uid gid mode f
  remote="$(field "$name" remote)"; type="$(field "$name" type)"
  uid="$(field "$name" uid)"; gid="$(field "$name" gid)"; mode="$(field "$name" mode)"
  f="$SECRETS_DIR/$name.yaml"
  [ -n "$remote" ] || { warn "skip '$name': not in manifest"; return 1; }
  [ -f "$f" ] || { warn "skip '$name': no encrypted file at $f"; return 1; }

  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run push $name  ($f → $REMOTE:$REMOTE_ROOT/$remote, $uid:$gid $mode)"
    return 0
  fi

  if decrypt_entry "$type" "$f" | ssh -o BatchMode=yes "$REMOTE" \
      "sudo -n sh -c 'umask 077; cat > \"\$1\"; chown $uid:$gid \"\$1\"; chmod $mode \"\$1\"' _ '$REMOTE_ROOT/$remote'"; then
    log "push $name → $REMOTE:$REMOTE_ROOT/$remote ($uid:$gid $mode)"
  else
    warn "push '$name' failed"
    return 1
  fi
}

verify_one() {
  local name="$1" remote type f local_d remote_d
  remote="$(field "$name" remote)"; type="$(field "$name" type)"
  f="$SECRETS_DIR/$name.yaml"
  [ -n "$remote" ] || { warn "skip '$name': not in manifest"; return 1; }
  [ -f "$f" ] || { warn "skip '$name': no encrypted file at $f"; return 1; }

  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run verify $name"
    return 0
  fi

  if [ "$type" = "dotenv" ]; then
    local_d="$(decrypt_entry dotenv "$f" | digest_pairs)"
    remote_d="$(ssh -o BatchMode=yes "$REMOTE" "sudo -n cat '$REMOTE_ROOT/$remote'" | digest_pairs)"
  else
    local_d="$(decrypt_entry binary "$f" | sha256sum | cut -d' ' -f1)"
    remote_d="$(ssh -o BatchMode=yes "$REMOTE" "sudo -n cat '$REMOTE_ROOT/$remote'" | sha256sum | cut -d' ' -f1)"
  fi

  if [ "$local_d" = "$remote_d" ]; then
    log "verify $name: MATCH"
  else
    warn "verify $name: MISMATCH"
    diff <(printf '%s\n' "$remote_d") <(printf '%s\n' "$local_d") \
      | sed 's/^/    /' >&2 || true
    return 1
  fi
}

RC=0
for name in "${NAMES[@]}"; do
  case "$MODE" in
    pull) pull_one "$name" || RC=1 ;;
    push) push_one "$name" || RC=1 ;;
    verify) verify_one "$name" || RC=1 ;;
  esac
done

exit "$RC"
