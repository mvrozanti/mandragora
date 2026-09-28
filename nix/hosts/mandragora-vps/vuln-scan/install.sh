#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REMOTE="${REMOTE:-opc@100.84.78.83}"

echo "→ pushing scan.sh to /usr/local/bin"
rsync -a "$HERE/scan.sh" "$REMOTE:/tmp/vuln-scan-vps.sh"
ssh "$REMOTE" 'sudo mv /tmp/vuln-scan-vps.sh /usr/local/bin/vuln-scan-vps.sh \
  && sudo chmod +x /usr/local/bin/vuln-scan-vps.sh \
  && sudo restorecon /usr/local/bin/vuln-scan-vps.sh'

echo "→ pushing systemd units"
rsync -a "$HERE/vuln-scan-vps.service" "$HERE/vuln-scan-vps.timer" "$REMOTE:/tmp/"
ssh "$REMOTE" 'sudo mv /tmp/vuln-scan-vps.service /tmp/vuln-scan-vps.timer /etc/systemd/system/ \
  && sudo systemctl daemon-reload \
  && sudo systemctl enable --now vuln-scan-vps.timer'

echo "→ running first scan now (downloads trivy DB on first run, ~1 min)"
ssh "$REMOTE" 'sudo systemctl start vuln-scan-vps.service && journalctl -u vuln-scan-vps.service -n 8 --no-pager'

echo "→ done. https://vuln.mvr.ac (mandragora-vps tab)"
