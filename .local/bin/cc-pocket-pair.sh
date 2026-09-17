#!/usr/bin/env bash
set -euo pipefail

RELAY_WS="${CC_POCKET_RELAY_WS:-ws://100.115.80.79:9090}"
PAIR_PORT="${CC_POCKET_PAIR_PORT:-8799}"

resp="$(curl -sS -m 8 -X POST "http://127.0.0.1:${PAIR_PORT}/pair")"
ticket="$(printf '%s' "$resp" | jq -r .ticket 2>/dev/null)"
acct="$(printf '%s' "$resp" | jq -r .accountId 2>/dev/null)"
dpk="$(printf '%s' "$resp" | jq -r .daemonPub 2>/dev/null)"

if [ -z "$ticket" ] || [ "$ticket" = null ] || [ -z "$acct" ] || [ "$acct" = null ] || [ -z "$dpk" ] || [ "$dpk" = null ]; then
  echo "cc-pocket-pair: daemon did not mint a ticket: ${resp:-<no response>}" >&2
  echo "cc-pocket-pair: is cc-pocket-daemon running and attached to the relay?" >&2
  exit 1
fi

url="ccpocket://pair?relay=${RELAY_WS}&acct=${acct}&dpk=${dpk}&ticket=${ticket}"

echo
echo "  Open CC Pairlet on your phone and scan this:"
echo
qrencode -t UTF8 -m 1 "$url"
echo
echo "  relay:  ${RELAY_WS}"
echo "  link:   ${url}"
echo
