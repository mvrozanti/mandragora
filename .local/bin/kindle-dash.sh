#!/usr/bin/env bash
set -euo pipefail

VM_URL="${VM_URL:-http://localhost:8428}"
KINDLE_HOST="${KINDLE_HOST:-100.80.53.92}"
KINDLE_PORT="${KINDLE_PORT:-22}"
REPO="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
RENDER_PY="$REPO/nix/hosts/mandragora-kindle/dash/render.py"
REMOTE_DIR=/mnt/us/mandragora/dash
REMOTE_FILE="$REMOTE_DIR/latest.png"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

[ -f "$RENDER_PY" ] || { echo "kindle-dash: no renderer at $RENDER_PY" >&2; exit 1; }
command -v jq >/dev/null || { echo "kindle-dash: jq not found" >&2; exit 1; }

SSH=(ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "root@$KINDLE_HOST")

vm_query() {
  curl -s --max-time 10 "$VM_URL/api/v1/query" --data-urlencode "query=$1"
}

scalar() {
  local promql="$1" default="${2:-}" val
  val=$(vm_query "$promql" | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true)
  [ -n "$val" ] && printf '%s' "$val" || printf '%s' "$default"
}

is_one() {
  [ "${1:-0}" = "1" ]
}

json_bool() {
  is_one "$1" && printf 'true' || printf 'false'
}

human_bytes() {
  LC_ALL=C awk -v b="${1:-0}" 'BEGIN{
    split("B K M G T P", u, " ")
    v = b + 0; i = 1
    while (v >= 1024 && i < 6) { v /= 1024; i++ }
    if (v >= 100 || v == int(v)) printf "%d%s", v, u[i]
    else printf "%.1f%s", v, u[i]
  }'
}

used_pct() {
  local avail="$1" total="$2"
  [ -z "$avail" ] || [ -z "$total" ] || [ "$total" = 0 ] && { printf ''; return; }
  LC_ALL=C awk -v a="$avail" -v t="$total" 'BEGIN{printf "%.0f", (1 - a / t) * 100}'
}

used_frac() {
  local avail="$1" total="$2"
  [ -z "$avail" ] || [ -z "$total" ] || [ "$total" = 0 ] && { printf 'null'; return; }
  LC_ALL=C awk -v a="$avail" -v t="$total" 'BEGIN{printf "%.4f", 1 - a / t}'
}

round0() {
  [ -z "${1:-}" ] && { printf ''; return; }
  LC_ALL=C awk -v v="$1" 'BEGIN{printf "%.0f", v}'
}

round1() {
  [ -z "${1:-}" ] && { printf ''; return; }
  LC_ALL=C awk -v v="$1" 'BEGIN{printf "%.1f", v}'
}

ratio_pct() {
  [ -z "${1:-}" ] && { printf ''; return; }
  LC_ALL=C awk -v v="$1" 'BEGIN{printf "%.0f", v * 100}'
}

fmt_uptime() {
  [ -z "${1:-}" ] && { printf '--'; return; }
  LC_ALL=C awk -v s="$1" 'BEGIN{
    s = int(s)
    d = int(s / 86400); s %= 86400
    h = int(s / 3600); s %= 3600
    m = int(s / 60)
    if (d > 0) printf "%dd %dh", d, h
    else if (h > 0) printf "%dh%02dm", h, m
    else printf "%dm", m
  }'
}

font_path() {
  fc-match --format='%{file}' "$1" 2>/dev/null
}

FONT_HEAVY=$(font_path "Iosevka Nerd Font:weight=heavy")
FONT_BOLD=$(font_path "Iosevka Nerd Font:bold")
FONT_REGULAR=$(font_path "Iosevka Nerd Font")
FONT_LIGHT=$(font_path "Iosevka Nerd Font:light")

for f in "$FONT_HEAVY" "$FONT_BOLD" "$FONT_REGULAR" "$FONT_LIGHT"; do
  [ -n "$f" ] && [ -f "$f" ] || { echo "kindle-dash: could not resolve Iosevka Nerd Font via fc-match" >&2; exit 1; }
done

echo "kindle-dash: querying $VM_URL"

desktop_up=$(scalar 'up{instance="mandragora-desktop",job="node"}' 0)
desktop_load=$(round1 "$(scalar 'node_load1{instance="mandragora-desktop"}')")
desktop_mem_avail=$(scalar 'node_memory_MemAvailable_bytes{instance="mandragora-desktop"}')
desktop_mem_total=$(scalar 'node_memory_MemTotal_bytes{instance="mandragora-desktop"}')
desktop_disk_avail=$(scalar 'node_filesystem_avail_bytes{instance="mandragora-desktop",mountpoint="/"}')
desktop_disk_total=$(scalar 'node_filesystem_size_bytes{instance="mandragora-desktop",mountpoint="/"}')
desktop_gpu_util=$(scalar 'nvidia_smi_utilization_gpu_ratio{instance="mandragora-desktop"}')
desktop_gpu_temp=$(round0 "$(scalar 'nvidia_smi_temperature_gpu{instance="mandragora-desktop"}')")

vps_up=$(scalar 'up{instance="mandragora-vps",job="node-vps"}' 0)
vps_load=$(round1 "$(scalar 'node_load1{instance="mandragora-vps"}')")
vps_mem_avail=$(scalar 'node_memory_MemAvailable_bytes{instance="mandragora-vps"}')
vps_mem_total=$(scalar 'node_memory_MemTotal_bytes{instance="mandragora-vps"}')
vps_disk_avail=$(scalar 'node_filesystem_avail_bytes{instance="mandragora-vps",mountpoint="/"}')
vps_disk_total=$(scalar 'node_filesystem_size_bytes{instance="mandragora-vps",mountpoint="/"}')

kindle_up=$(scalar 'up{instance="mandragora-kindle",job="kindle"}' 0)
kindle_battery=$(round0 "$(scalar 'kindle_battery_percent')")
kindle_charging=$(scalar 'kindle_charging' 0)
kindle_storage=$(round0 "$(scalar 'kindle_storage_used_percent')")
kindle_uptime_raw=$(scalar 'kindle_uptime_seconds')
kindle_art=$(round0 "$(scalar 'kindle_art_images')")

services_json=$(vm_query 'kindle_service_up{instance="mandragora-kindle"}')
svc_up() {
  printf '%s' "$services_json" | jq -r --arg s "$1" '(.data.result[] | select(.metric.service == $s) | .value[1]) // "0"'
}
svc_dropbear=$(svc_up dropbear)
svc_koreader=$(svc_up koreader)
svc_tailscaled=$(svc_up tailscaled)

desktop_mem_pct=$(used_pct "$desktop_mem_avail" "$desktop_mem_total")
desktop_mem_frac=$(used_frac "$desktop_mem_avail" "$desktop_mem_total")
desktop_disk_frac=$(used_frac "$desktop_disk_avail" "$desktop_disk_total")
vps_mem_pct=$(used_pct "$vps_mem_avail" "$vps_mem_total")
vps_mem_frac=$(used_frac "$vps_mem_avail" "$vps_mem_total")
vps_disk_frac=$(used_frac "$vps_disk_avail" "$vps_disk_total")

date_str=$(date '+%d %b %Y' | tr '[:lower:]' '[:upper:]')
time_str=$(date '+%H:%M')
generated_str="rendered $(date '+%H:%M:%S')"

jq -n \
  --arg date "$date_str" \
  --arg time "$time_str" \
  --arg generated "$generated_str" \
  --arg footer "MANDRAGORA ▸ TAILNET STATUS" \
  --argjson desktop_up "$(json_bool "$desktop_up")" \
  --arg desktop_load "${desktop_load:---}" \
  --arg desktop_mem_pct "${desktop_mem_pct:+${desktop_mem_pct}%}" \
  --argjson desktop_mem_frac "${desktop_mem_frac:-null}" \
  --arg desktop_mem_sub "$([ -n "$desktop_mem_avail" ] && echo "$(human_bytes "$desktop_mem_avail") free" || echo '')" \
  --arg desktop_disk_free "$([ -n "$desktop_disk_avail" ] && human_bytes "$desktop_disk_avail" || echo '--')" \
  --argjson desktop_disk_frac "${desktop_disk_frac:-null}" \
  --arg desktop_disk_sub "$([ -n "$desktop_disk_total" ] && echo "of $(human_bytes "$desktop_disk_total")" || echo '')" \
  --arg desktop_gpu_pct "$([ -n "$desktop_gpu_util" ] && echo "$(ratio_pct "$desktop_gpu_util")%" || echo '--')" \
  --arg desktop_gpu_sub "$([ -n "$desktop_gpu_temp" ] && echo "${desktop_gpu_temp}°C" || echo '')" \
  --argjson vps_up "$(json_bool "$vps_up")" \
  --arg vps_load "${vps_load:---}" \
  --arg vps_mem_pct "${vps_mem_pct:+${vps_mem_pct}%}" \
  --argjson vps_mem_frac "${vps_mem_frac:-null}" \
  --arg vps_mem_sub "$([ -n "$vps_mem_avail" ] && echo "$(human_bytes "$vps_mem_avail") free" || echo '')" \
  --arg vps_disk_free "$([ -n "$vps_disk_avail" ] && human_bytes "$vps_disk_avail" || echo '--')" \
  --argjson vps_disk_frac "${vps_disk_frac:-null}" \
  --arg vps_disk_sub "$([ -n "$vps_disk_total" ] && echo "of $(human_bytes "$vps_disk_total")" || echo '')" \
  --argjson kindle_up "$(json_bool "$kindle_up")" \
  --arg kindle_battery "${kindle_battery:+${kindle_battery}%}" \
  --arg kindle_battery_sub "$(is_one "$kindle_charging" && echo charging || echo 'on battery')" \
  --argjson kindle_battery_frac "$([ -n "$kindle_battery" ] && LC_ALL=C awk -v v="$kindle_battery" 'BEGIN{printf "%.2f", v/100}' || echo null)" \
  --arg kindle_storage "${kindle_storage:+${kindle_storage}%}" \
  --argjson kindle_storage_frac "$([ -n "$kindle_storage" ] && LC_ALL=C awk -v v="$kindle_storage" 'BEGIN{printf "%.2f", v/100}' || echo null)" \
  --arg kindle_uptime "$(fmt_uptime "$kindle_uptime_raw")" \
  --arg kindle_art "${kindle_art:---}" \
  --argjson svc_dropbear "$(json_bool "$svc_dropbear")" \
  --argjson svc_koreader "$(json_bool "$svc_koreader")" \
  --argjson svc_tailscaled "$(json_bool "$svc_tailscaled")" \
  '{
    date: $date, time: $time, generated: $generated, footer: $footer,
    hosts: [
      {
        name: "desktop", label: "Desktop",
        detail: "ryzen 9 7900x · rtx 5070 ti",
        up: $desktop_up,
        metrics: [
          {label: "Load 1m", value: (if $desktop_up then $desktop_load else "--" end)},
          {label: "Memory used", value: (if $desktop_mem_pct == "" then "--" else $desktop_mem_pct end), bar: $desktop_mem_frac, sub: (if $desktop_mem_sub == "" then null else $desktop_mem_sub end)},
          {label: "Disk free /", value: $desktop_disk_free, bar: $desktop_disk_frac, sub: (if $desktop_disk_sub == "" then null else $desktop_disk_sub end)},
          {label: "GPU", value: $desktop_gpu_pct, sub: (if $desktop_gpu_sub == "" then null else $desktop_gpu_sub end)}
        ]
      },
      {
        name: "vps", label: "VPS",
        detail: "oracle cloud · mandragora-vps",
        up: $vps_up,
        metrics: [
          {label: "Load 1m", value: (if $vps_up then $vps_load else "--" end)},
          {label: "Memory used", value: (if $vps_mem_pct == "" then "--" else $vps_mem_pct end), bar: $vps_mem_frac, sub: (if $vps_mem_sub == "" then null else $vps_mem_sub end)},
          {label: "Disk free /", value: $vps_disk_free, bar: $vps_disk_frac, sub: (if $vps_disk_sub == "" then null else $vps_disk_sub end)}
        ]
      },
      {
        name: "kindle", label: "Kindle",
        detail: "paperwhite 12 · tailnet",
        up: $kindle_up,
        metrics: [
          {label: "Battery", value: (if $kindle_battery == "" then "--" else $kindle_battery end), bar: $kindle_battery_frac, sub: $kindle_battery_sub},
          {label: "Storage used", value: (if $kindle_storage == "" then "--" else $kindle_storage end), bar: $kindle_storage_frac},
          {label: "Uptime", value: $kindle_uptime},
          {label: "Art images", value: $kindle_art}
        ],
        services: [
          {label: "dropbear", up: $svc_dropbear},
          {label: "koreader", up: $svc_koreader},
          {label: "tailscaled", up: $svc_tailscaled}
        ]
      }
    ]
  }' > "$WORKDIR/data.json"

echo "kindle-dash: rendering"
nix shell --impure --expr 'let p = import <nixpkgs> {}; in p.python3.withPackages (ps: [ ps.pillow ])' --command python3 \
  "$RENDER_PY" \
  --data "$WORKDIR/data.json" \
  --out "$WORKDIR/latest.png" \
  --font-heavy "$FONT_HEAVY" --font-bold "$FONT_BOLD" --font-regular "$FONT_REGULAR" --font-light "$FONT_LIGHT"

echo "kindle-dash: pushing to $KINDLE_HOST:$REMOTE_FILE"
"${SSH[@]}" "mkdir -p $REMOTE_DIR && cat > $REMOTE_FILE && chmod 644 $REMOTE_FILE" < "$WORKDIR/latest.png"

echo "kindle-dash: done"
