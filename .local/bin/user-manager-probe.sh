#!/usr/bin/env bash
if out=$(timeout 20 systemctl --user is-system-running 2>&1); then
  rc=0
else
  rc=$?
fi
case "$out" in
  running | degraded | starting | initializing | maintenance) exit 0 ;;
esac
echo "user manager not answering (rc=$rc): $out" >&2
exit 1
