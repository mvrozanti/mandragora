#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REMOTE="${REMOTE:-opc@100.84.78.83}"

echo "→ pushing refresh.sh to /usr/local/bin"
rsync -a "$HERE/refresh.sh" "$REMOTE:/tmp/stack-refresh.sh"
ssh "$REMOTE" 'sudo mv /tmp/stack-refresh.sh /usr/local/bin/stack-refresh.sh \
  && sudo chmod +x /usr/local/bin/stack-refresh.sh \
  && sudo restorecon /usr/local/bin/stack-refresh.sh'

echo "→ pushing systemd units"
rsync -a "$HERE/stack-refresh.service" "$HERE/stack-refresh.timer" "$REMOTE:/tmp/"
ssh "$REMOTE" 'sudo mv /tmp/stack-refresh.service /tmp/stack-refresh.timer /etc/systemd/system/ \
  && sudo restorecon /etc/systemd/system/stack-refresh.service /etc/systemd/system/stack-refresh.timer \
  && sudo systemctl daemon-reload \
  && sudo systemctl enable --now stack-refresh.timer'

echo "→ dry run (pulls, recreates nothing)"
ssh "$REMOTE" 'REFRESH_DRY_RUN=1 /usr/local/bin/stack-refresh.sh'

echo "→ done. next real run: $(ssh "$REMOTE" 'systemctl list-timers stack-refresh.timer --no-pager | sed -n 2p')"
