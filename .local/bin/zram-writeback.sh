#!/usr/bin/env bash
set -euo pipefail

zram=/sys/block/zram0
backing=$(cat "$zram/backing_dev")
[ "$backing" != none ] || exit 0

echo 1 > "$zram/writeback_limit_enable"
echo 524288 > "$zram/writeback_limit"
echo huge > "$zram/writeback" || true
echo idle > "$zram/writeback" || true
echo all > "$zram/idle"
