#!/usr/bin/env bash
set -uo pipefail

SLOTS_DIR="${REFRESH_SLOTS_DIR:-/home/opc}"
STAMPS_DIR="${REFRESH_STAMPS_DIR:-/home/opc/.deployed}"
STATIC_DIR="${VULN_STATIC_DIR:-/home/opc/vuln/static}"
STATE_DIR="${REFRESH_STATE_DIR:-/home/opc/.local/state/stack-refresh}"
HOST="mandragora-vps"
SETTLE="${REFRESH_SETTLE_SECONDS:-180}"
QUIET_RUN="${REFRESH_QUIET_RUN_SECONDS:-30}"
DRY_RUN="${REFRESH_DRY_RUN:-0}"
HOLD=" ${REFRESH_HOLD:-} "

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock -n 9 || { echo "another refresh holds $STATE_DIR/lock"; exit 0; }

HELD="$STATE_DIR/held.json"
[ -s "$HELD" ] || echo '{}' >"$HELD"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: >"$WORK/updated" ; : >"$WORK/failed" ; : >"$WORK/skipped"

record() {
  local kind="$1"; shift
  jq -cn "$@" >>"$WORK/$kind"
}
held_get() { jq -r --arg k "$1" '.[$k] // ""' "$HELD"; }
held_set() { jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$HELD" >"$HELD.tmp" && mv "$HELD.tmp" "$HELD"; }
held_del() { jq --arg k "$1" 'del(.[$k])' "$HELD" >"$HELD.tmp" && mv "$HELD.tmp" "$HELD"; }

stacks() {
  if [ $# -gt 0 ]; then
    printf '%s\n' "$@"
    return
  fi
  local stamp name
  for stamp in "$STAMPS_DIR"/*; do
    [ -f "$stamp" ] || continue
    name="$(basename "$stamp")"
    [ -f "$SLOTS_DIR/$name/docker-compose.yml" ] && printf '%s\n' "$name"
  done
}

container_of() { docker compose ps -q "$1" 2>/dev/null | head -n1; }

settle() {
  local svc="$1" deadline=$((SECONDS + SETTLE)) cid state health restarts first_restarts="" running_since=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    cid="$(container_of "$svc")"
    if [ -z "$cid" ]; then
      sleep 5
      continue
    fi
    read -r state health restarts < <(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} {{.RestartCount}}' "$cid" 2>/dev/null)
    [ -n "$first_restarts" ] || first_restarts="$restarts"
    case "$state" in
      exited|dead) echo "container $state"; return 1 ;;
      restarting) echo "container is restarting"; return 1 ;;
    esac
    [ "$restarts" = "$first_restarts" ] || { echo "container restarted $((restarts - first_restarts)) time(s)"; return 1; }
    case "$health" in
      healthy) return 0 ;;
      unhealthy) echo "healthcheck reports unhealthy"; return 1 ;;
      none)
        [ -n "$running_since" ] || running_since="$SECONDS"
        [ $((SECONDS - running_since)) -ge "$QUIET_RUN" ] && return 0
        ;;
    esac
    sleep 5
  done
  echo "not healthy within ${SETTLE}s"
  return 1
}

refresh_stack() {
  local name="$1" dir="$SLOTS_DIR/$1" svc image cid old_id pre_id new_id key reason
  local -a want=() images=() olds=() news=()
  cd "$dir" || { record skipped --arg s "$name" '{stack: $s, reason: "no slot directory"}'; return; }
  while IFS=$'\t' read -r svc image; do
    [ -n "$svc" ] || continue
    if [[ "$HOLD" == *" $name "* || "$HOLD" == *" $name/$svc "* ]]; then
      record skipped --arg s "$name" --arg v "$svc" --arg i "$image" '{stack: $s, service: $v, image: $i, reason: "held by REFRESH_HOLD"}'
      continue
    fi
    cid="$(container_of "$svc")"
    [ -n "$cid" ] || continue
    old_id="$(docker inspect -f '{{.Image}}' "$cid")"
    pre_id="$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null)"
    if ! docker compose pull --quiet "$svc" >/dev/null 2>&1; then
      record skipped --arg s "$name" --arg v "$svc" --arg i "$image" '{stack: $s, service: $v, image: $i, reason: "pull failed (local-only image or registry unreachable)"}'
      continue
    fi
    new_id="$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null)"
    if [ "$DRY_RUN" = 1 ] && [ -n "$pre_id" ] && [ "$new_id" != "$pre_id" ]; then
      docker tag "$pre_id" "$image"
    fi
    [ -n "$new_id" ] && [ "$new_id" != "$old_id" ] || continue
    key="$name/$svc"
    if [ "$(held_get "$key")" = "$new_id" ]; then
      record skipped --arg s "$name" --arg v "$svc" --arg i "$image" --arg t "$new_id" '{stack: $s, service: $v, image: $i, to: $t, reason: "held: this image already failed once"}'
      continue
    fi
    want+=("$svc") images+=("$image") olds+=("$old_id") news+=("$new_id")
  done < <(docker compose config --format json 2>/dev/null | jq -r '.services | to_entries[] | select(.value.build == null and .value.image != null) | "\(.key)\t\(.value.image)"')

  [ "${#want[@]}" -gt 0 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    local i
    for i in "${!want[@]}"; do
      record updated --arg s "$name" --arg v "${want[$i]}" --arg i "${images[$i]}" --arg f "${olds[$i]}" --arg t "${news[$i]}" '{stack: $s, service: $v, image: $i, from: $f, to: $t, dry_run: true}'
    done
    return 0
  fi

  docker compose up -d --no-build --no-deps "${want[@]}" >/dev/null 2>&1
  local i
  for i in "${!want[@]}"; do
    key="$name/${want[$i]}"
    if reason="$(settle "${want[$i]}")"; then
      held_del "$key"
      record updated --arg s "$name" --arg v "${want[$i]}" --arg i "${images[$i]}" --arg f "${olds[$i]}" --arg t "${news[$i]}" '{stack: $s, service: $v, image: $i, from: $f, to: $t}'
    else
      docker tag "${olds[$i]}" "${images[$i]}"
      docker compose up -d --no-build --no-deps "${want[$i]}" >/dev/null 2>&1
      held_set "$key" "${news[$i]}"
      record failed --arg s "$name" --arg v "${want[$i]}" --arg i "${images[$i]}" --arg f "${olds[$i]}" --arg t "${news[$i]}" --arg r "$reason" '{stack: $s, service: $v, image: $i, from: $f, to: $t, reason: $r, rolled_back: true}'
    fi
  done
}

while read -r name; do
  [ -n "$name" ] || continue
  refresh_stack "$name"
done < <(stacks "$@")

[ "$DRY_RUN" = 1 ] || docker image prune -f >/dev/null 2>&1

out="$STATIC_DIR/refresh-$HOST.json"
tmp="$(mktemp "$STATIC_DIR/.refresh.XXXXXX")"
jq -n \
  --arg host "$HOST" \
  --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson dry "$([ "$DRY_RUN" = 1 ] && echo true || echo false)" \
  --slurpfile updated "$WORK/updated" \
  --slurpfile failed "$WORK/failed" \
  --slurpfile skipped "$WORK/skipped" \
  '{schema: 1, host: $host, generated: $generated, dry_run: $dry, updated: $updated, failed: $failed, skipped: $skipped}' >"$tmp"
chmod 0644 "$tmp"
mv "$tmp" "$out"

jq -r '"refresh: \(.updated | length) updated, \(.failed | length) rolled back, \(.skipped | length) skipped\(if .dry_run then " (dry run)" else "" end)"' "$out"
jq -r '.failed[] | "  rolled back \(.stack)/\(.service) (\(.image)): \(.reason)"' "$out"
[ "$(jq '.failed | length' "$out")" -eq 0 ]
