#!/usr/bin/env bash
set -euo pipefail

exec systemd-run --user --scope --slice=app.slice --collect --quiet \
  steam steam://rungameid/2483190
