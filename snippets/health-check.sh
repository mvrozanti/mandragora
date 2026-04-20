#!/usr/bin/env bash
# health-check.sh — Mandragora system health audit.
# Outputs tagged lines (OK/INFO/WARN). Exits 1 if any WARN is found.
# Substituted at build time: @diskWarnThreshold@ @logFile@

set -euo pipefail

DISK_WARN_THRESHOLD=@diskWarnThreshold@
LOG_FILE=@logFile@

WARN=0
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TIMESTAMP] $1"; }

# --- Disk usage ---
while IFS= read -r line; do
  usage=$(echo "$line" | awk '{print $1}' | tr -d '%')
  mount=$(echo "$line" | awk '{print $2}')
  [ -z "$usage" ] && continue
  if [ "$usage" -ge "$DISK_WARN_THRESHOLD" ]; then
    log "WARN disk ${mount} at ${usage}% (threshold ${DISK_WARN_THRESHOLD}%)"
    WARN=1
  else
    log "OK   disk ${mount} at ${usage}%"
  fi
done < <(df --output=pcent,target | tail -n +2 | grep -v "^[[:space:]]*$")

# --- SMART health ---
for dev in /dev/nvme* /dev/sd* /dev/vd*; do
  [ -e "$dev" ] || continue
  # Skip partitions: non-nvme devices ending in a digit, or NVMe partitions (nvme*p[0-9])
  [[ "$dev" =~ [0-9]$ && ! "$dev" =~ nvme[0-9]+n[0-9]+$ ]] && continue
  smart_out=$(smartctl -H "$dev" 2>&1 || true)
  if echo "$smart_out" | grep -qE "PASSED|OK"; then
    log "OK   SMART ${dev} healthy"
  elif echo "$smart_out" | grep -qE "FAILED|FAILING"; then
    log "WARN SMART ${dev} reports failure"
    WARN=1
  else
    log "INFO SMART ${dev} status unknown or unsupported"
  fi
done

# --- Failed systemd units ---
failed=$(systemctl --failed --no-legend --no-pager 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
if [ -n "${failed// }" ]; then
  log "WARN failed units: ${failed}"
  WARN=1
else
  log "OK   no failed systemd units"
fi

# --- Listening ports (snapshot) ---
port_count=$(ss -tlnp 2>/dev/null | tail -n +2 | wc -l)
log "INFO ${port_count} TCP listening sockets active"

# --- Thermal sensors ---
if command -v sensors &>/dev/null; then
  while IFS= read -r line; do
    temp=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+.C' | grep -oE '[0-9]+\.[0-9]+' | head -1)
    label=$(echo "$line" | awk -F: '{print $1}' | xargs)
    [ -z "$temp" ] && continue
    temp_int=${temp%.*}
    if [ "$temp_int" -ge 90 ]; then
      log "WARN thermal ${label} at ${temp}°C"
      WARN=1
    elif [ "$temp_int" -ge 75 ]; then
      log "INFO thermal ${label} at ${temp}°C (elevated)"
    else
      log "OK   thermal ${label} at ${temp}°C"
    fi
  done < <(sensors 2>/dev/null | grep -E '[0-9]+\.[0-9]+' || true)
else
  log "INFO sensors not available"
fi

# --- Memory pressure ---
total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
avail=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
if [ "$total" -gt 0 ]; then
  used_pct=$(( (total - avail) * 100 / total ))
  if [ "$used_pct" -ge 90 ]; then
    log "WARN memory at ${used_pct}% (${avail} kB available)"
    WARN=1
  elif [ "$used_pct" -ge 75 ]; then
    log "INFO memory at ${used_pct}% (${avail} kB available, elevated)"
  else
    log "OK   memory at ${used_pct}% (${avail} kB available)"
  fi
else
  log "INFO memory info unavailable"
fi

# --- Btrfs scrub age ---
for mp in / /nix /persistent; do
  mountpoint -q "$mp" 2>/dev/null || continue
  scrub_out=$(btrfs scrub status "$mp" 2>/dev/null || true)
  last_scrub=$(echo "$scrub_out" | grep -i 'scrub started\|last scrub' | tail -1)
  if [ -z "$last_scrub" ]; then
    log "WARN btrfs scrub ${mp}: no scrub record — run 'btrfs scrub start ${mp}'"
    WARN=1
  else
    log "INFO btrfs scrub ${mp}: ${last_scrub}"
  fi
done

# --- Exit ---
if [ "$WARN" -eq 1 ]; then
  log "WARN audit complete — warnings detected"
  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$TIMESTAMP] WARN audit complete — see journalctl -u audit-watch or audit-digest" >> "$LOG_FILE"
  fi
  exit 1
else
  log "OK   audit complete — system healthy"
  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$TIMESTAMP] OK   audit clean" >> "$LOG_FILE"
  fi
fi
