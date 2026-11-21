#!/usr/bin/env bash
set -euo pipefail

REPO="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
export MANDRAGORA_REPO="$REPO"
PHONE="$REPO/nix/hosts/mandragora-phone"
APP="$PHONE/app"
QUALITY="$PHONE/quality"
BRIDGE="$PHONE/bridge"
CLAUDE_BRIDGE="$REPO/.local/share/claude-bridge"
GPU_LOCK="$REPO/.local/share/gpu-lock"
MODE="${1:-full}"
RUFF_RULES="F,E9,B,ASYNC,PLE,RUF006"

case "$MODE" in
  full|fast|baseline) ;;
  *) echo "usage: phone-gate [full|fast|baseline]" >&2; exit 2 ;;
esac

if [ -z "${PHONE_GATE_INSIDE:-}" ]; then
  exec env PHONE_GATE_INSIDE=1 nix develop "$REPO#phone" -c "$0" "$@"
fi

export PYTHONDONTWRITEBYTECODE=1
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
START=$SECONDS

floor() { sed -n "s/^$1=//p" "$QUALITY/coverage-floors"; }

detekt_args=(--input "$APP/app/src/main/kotlin,$APP/app/src/test/kotlin" --config "$QUALITY/detekt.yml" --build-upon-default-config --baseline "$QUALITY/detekt-baseline.xml")
pyright_args=(-p "$REPO/pyrightconfig.json" --pythonpath "$(command -v python3)" --baselinefile "$QUALITY/pyright-baseline.json")

if [ "$MODE" = baseline ]; then
  echo "phone-gate: rewriting the detekt, basedpyright and lint baselines"
  detekt "${detekt_args[@]}" --create-baseline > /dev/null
  basedpyright "${pyright_args[@]}" --writebaseline > /dev/null || true
  (cd "$APP" && ./gradlew --quiet updateLintBaseline)
  echo "phone-gate: baselines rewritten; review the diff before committing it"
  exit 0
fi

timed() {
  local label="$1" began=$SECONDS
  shift
  if "$@"; then
    printf 'phone-gate: ok    %-52s %4s s\n' "$label" "$((SECONDS - began))"
  else
    printf 'phone-gate: FAIL  %-52s %4s s\n' "$label" "$((SECONDS - began))"
    return 1
  fi
}

gradle() { (cd "$APP" && ./gradlew --quiet "$@"); }

pytest_cov() {
  local dir="$1" module="$2" name="$3"
  (cd "$dir" && COVERAGE_FILE="$SCRATCH/coverage-$name" PYTHONPATH="$GPU_LOCK" python3 -m pytest -q -p no:cacheprovider \
    --cov="$module" --cov-report=term --cov-precision=2 --cov-fail-under="$(floor "$name")" tests)
}

kotlin_checks() {
  local tasks=(testDebugUnitTest koverVerifyDebug) label="unit tests, logic coverage >= 80%"
  if [ "$MODE" = full ]; then
    tasks+=(lintDebug)
    label="$label, android lint"
  fi
  timed "kotlin: detekt" detekt "${detekt_args[@]}" || return 1
  timed "kotlin: $label" gradle "${tasks[@]}"
}

python_checks() {
  timed "python: ruff $RUFF_RULES" ruff check --no-cache --quiet --select "$RUFF_RULES" "$BRIDGE" "$PHONE/ask" "$CLAUDE_BRIDGE" || return 1
  timed "python: basedpyright, new errors only" basedpyright "${pyright_args[@]}" --level error || return 1
  timed "python: phone-bridge tests, coverage >= $(floor phone-bridge)%" pytest_cov "$BRIDGE" server phone-bridge || return 1
  timed "python: claude-bridge tests, coverage >= $(floor claude-bridge)%" pytest_cov "$CLAUDE_BRIDGE" app claude-bridge
}

if [ "$MODE" = full ]; then
  PHONE_SMOKE_INSIDE=1 PHONE_EMU_INSIDE=1 bash "$REPO/.local/bin/phone-smoke.sh" boot
fi

kotlin_checks > "$SCRATCH/kotlin.log" 2>&1 &
kotlin_pid=$!
python_checks > "$SCRATCH/python.log" 2>&1 &
python_pid=$!

failed=0
wait "$kotlin_pid" || failed=1
grep -vE "is dirty|isLinux is deprecated" "$SCRATCH/kotlin.log" || true
wait "$python_pid" || failed=1
grep -vE "is dirty|isLinux is deprecated" "$SCRATCH/python.log" || true

if [ "$failed" -ne 0 ]; then
  [ "$MODE" = full ] && { adb -s "emulator-${PHONE_EMU_PORT:-5560}" emu kill > /dev/null 2>&1 || true; }
  echo "phone-gate: FAILED after $((SECONDS - START)) s"
  exit 1
fi

if [ "$MODE" = full ]; then
  timed "emulator smoke test: launch, lock, reboot" env PHONE_SMOKE_INSIDE=1 PHONE_EMU_INSIDE=1 PHONE_SMOKE_BOOTED=1 \
    bash "$REPO/.local/bin/phone-smoke.sh" check || { echo "phone-gate: FAILED after $((SECONDS - START)) s"; exit 1; }
fi

echo "phone-gate: every $MODE check passed in $((SECONDS - START)) s"
