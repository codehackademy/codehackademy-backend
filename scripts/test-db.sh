#!/usr/bin/env bash
# Runs migrations + RLS tests against a throwaway local PostgreSQL 16 cluster (no Supabase required).
set -euo pipefail
PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
DIR=$(mktemp -d /tmp/chk-pg.XXXXXX); PORT=${PGPORT:-54329}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
run() { if [ "$(id -u)" = 0 ]; then chown postgres "$DIR"; runuser -u postgres -- "$@"; else "$@"; fi; }
cleanup() { run "$PGBIN/pg_ctl" -D "$DIR/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$DIR"; }
trap cleanup EXIT
run "$PGBIN/initdb" -D "$DIR/data" -A trust >/dev/null
run "$PGBIN/pg_ctl" -D "$DIR/data" -o "-p $PORT -k $DIR" -l "$DIR/pg.log" -w start >/dev/null
PSQL=("$PGBIN/psql" -h "$DIR" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q -X)
run "${PSQL[@]}" -d postgres -c "create database chk_test" >/dev/null
q() { run "${PSQL[@]}" -d chk_test "$@"; }
q -f "$ROOT/tests/db/00_supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do echo "migrate: $(basename "$f")"; q -f "$f"; done
q -f "$ROOT/tests/db/rls.test.sql" 2>&1 | sed -E 's/^psql:[^ ]+ //' | grep -E "ok - |FAIL|ERROR|PASSED"
