#!/usr/bin/env bash
set -euo pipefail
PROJ=/home/m/Projects/chess-lens-ultimate
cd "$PROJ"
set -a
. "$PROJ/.env"
set +a
CLERK_SECRET_KEY="$(cat /run/secrets/clerk/secret)"
export CLERK_SECRET_KEY
export CLERK_AUTHORIZED_PARTIES="https://chess.mvr.ac,http://localhost:5173"
export PATH="$HOME/.local/state/chess-lens/stockfish/bin:$PATH:/etc/profiles/per-user/m/bin:/run/current-system/sw/bin"
JAR=""
for candidate in "$PROJ"/backend/build/libs/*-SNAPSHOT.jar; do
  case "$candidate" in *plain*) continue ;; esac
  if [ -z "$JAR" ] || [ "$candidate" -nt "$JAR" ]; then
    JAR="$candidate"
  fi
done
exec java -Xmx3g -XX:G1PeriodicGCInterval=60000 -jar "$JAR"
