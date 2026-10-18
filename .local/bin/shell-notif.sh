#!/usr/bin/env bash
set -euo pipefail

systemctl --user is-active --quiet mandragora-shell.service || exit 1
exec mandragora-shell notif "$@"
