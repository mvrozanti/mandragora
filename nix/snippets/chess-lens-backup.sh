#!/usr/bin/env bash
: "${COMPOSE_DIR:?COMPOSE_DIR must be set}"
: "${REMOTE_USER:?REMOTE_USER must be set}"
: "${VPS_HOST:?VPS_HOST must be set}"
: "${REMOTE_DIR:?REMOTE_DIR must be set}"
: "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE must be set}"

export RESTIC_REPOSITORY="sftp:${REMOTE_USER}@${VPS_HOST}:${REMOTE_DIR}"
export RESTIC_PASSWORD_FILE

stage="${XDG_STATE_HOME:-$HOME/.local/state}/chess-lens/backup"
local_dir="$COMPOSE_DIR/backups"
name="chesslens-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$stage" "$local_dir"
chmod 0777 "$local_dir"

fail() {
  echo "chess-lens-backup: $1" >&2
  exit 1
}

docker exec backend-postgres-1 sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$stage/postgres.dump" \
  || fail "pg_dump failed"
[ -s "$stage/postgres.dump" ] || fail "the postgres dump is empty"

docker exec backend-redis-1 redis-cli --rdb /tmp/backup.rdb > /dev/null || fail "the redis snapshot failed"
docker cp backend-redis-1:/tmp/backup.rdb "$stage/redis.rdb" || fail "could not copy the redis snapshot"

docker start clickhouse > /dev/null || fail "could not start clickhouse"
for _ in $(seq 1 60); do
  docker exec clickhouse wget -qO- http://127.0.0.1:8123/ping > /dev/null 2>&1 && break
  sleep 2
done
docker exec clickhouse wget -qO- http://127.0.0.1:8123/ping > /dev/null 2>&1 || fail "clickhouse did not answer within two minutes"
docker exec clickhouse clickhouse-client -q "BACKUP DATABASE chesslens TO File('/backups/$name')" > /dev/null \
  || fail "the clickhouse backup failed"
docker exec clickhouse chmod -R a+rX "/backups/$name" || fail "could not open the clickhouse backup for reading"
[ -f "$local_dir/$name/.backup" ] || fail "no clickhouse backup manifest at $local_dir/$name"
docker exec clickhouse sh -c "find /backups -mindepth 1 -maxdepth 1 -name 'chesslens-*' ! -name '$name' -exec rm -rf {} +"

restic cat config > /dev/null 2>&1 || restic init
restic backup --tag chess-lens --group-by tags "$stage" "$local_dir/$name"
restic forget --tag chess-lens --group-by tags --keep-daily 14 --keep-weekly 8 --keep-monthly 6 --prune
restic check --read-data-subset=2%

echo "chess-lens-backup: $name stored in $RESTIC_REPOSITORY"
