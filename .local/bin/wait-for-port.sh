#!/usr/bin/env bash
set -euo pipefail
host=$1
port=$2
timeout=${3:-60}
deadline=$((SECONDS + timeout))
until (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "wait-for-port: $host:$port not listening after ${timeout}s" >&2
    exit 1
  fi
  sleep 0.2
done
