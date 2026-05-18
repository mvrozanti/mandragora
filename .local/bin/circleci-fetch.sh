#!/usr/bin/env bash
#
# circleci-fetch — query the CircleCI API using the sops-managed token.
#
# The token lives at /run/secrets/circleci/api_key (declared in
# nix/modules/core/secrets.nix, owner=m mode=0400). It is read into a
# bash here-doc and fed to curl via --config (stdin), so the value
# never appears on any command line or in /proc/<pid>/cmdline.
#
# Usage:
#   circleci-fetch <path>           # GET https://circleci.com/api/v2/<path>
#   circleci-fetch v1.1 <path>      # GET https://circleci.com/api/v1.1/<path>
#
# Common paths (chess-lens-ultimate examples):
#   project/gh/mvrozanti/chess-lens-ultimate/job/<num>
#   project/gh/mvrozanti/chess-lens-ultimate/job/<num>/tests
#   v1.1 project/github/mvrozanti/chess-lens-ultimate/<build_num>
#   v1.1 project/github/mvrozanti/chess-lens-ultimate/<build_num>/output/<step>/0

set -euo pipefail

if [[ -z "${CIRCLECI_TOKEN-}" ]]; then
    if [[ -r /run/secrets/circleci/api_key ]]; then
        CIRCLECI_TOKEN="$(< /run/secrets/circleci/api_key)"
    else
        echo "circleci-fetch: \$CIRCLECI_TOKEN unset and /run/secrets/circleci/api_key not readable" >&2
        exit 1
    fi
fi

base="https://circleci.com/api/v2"
if [[ "${1:-}" == "v1.1" ]]; then
    base="https://circleci.com/api/v1.1"
    shift
fi

if [[ $# -eq 0 ]]; then
    cat >&2 <<'USAGE'
usage: circleci-fetch [v1.1] <path>
  path is appended to https://circleci.com/api/<v2|v1.1>/
  the token is read from /run/secrets/circleci/api_key (sops-managed).
USAGE
    exit 2
fi

path="$1"
url="${base}/${path#/}"

curl --silent --fail-with-body --show-error --url "$url" --config - <<EOF
header = "Circle-Token: ${CIRCLECI_TOKEN}"
EOF
