#!/usr/bin/env bash
# Generate load with three distinct wait events for the Performance Insights demo.
#   sql/pi/load.sh            # all phases: cpu, lock, io, with a gap between them
#   sql/pi/load.sh lock       # one phase only (handy on stage)
#   DURATION=90 GAP=30 sql/pi/load.sh
# Needs the SSM tunnel on localhost:15432. Run sql/00b_reset.sql afterwards.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
DURATION="${DURATION:-60}"
GAP="${GAP:-30}"

export PGHOST=localhost PGPORT="${PGPORT:-15432}" PGDATABASE=demo PGUSER=demo_admin PGSSLMODE=require
if [[ -z "${PGPASSWORD:-}" ]]; then
  secret_arn="$(terraform -chdir="$repo/terraform" output -raw master_secret_arn)"
  PGPASSWORD="$(aws secretsmanager get-secret-value --region ap-southeast-1 --secret-id "$secret_arn" \
    --query SecretString --output text | jq -r .password)"
  export PGPASSWORD
fi

say() { echo "[$(date +%H:%M:%S)] $*"; }

phase_cpu() {
  say "cpu: 6 sessions x Seq Scan for ${DURATION}s (expect CPU above the 2 vCPU line)"
  pgbench -n -c 6 -j 6 -T "$DURATION" -f "$here/cpu.sql" > /dev/null
}

phase_lock() {
  say "lock: 1 session holds row id=1, 4 sessions wait for ${DURATION}s (expect Lock:transactionid / Lock:tuple)"
  psql -X -q -c "BEGIN; UPDATE orders SET note = 'pi-lock-holder' WHERE id = 1; SELECT pg_sleep($DURATION); ROLLBACK;" > /dev/null &
  holder=$!
  sleep 2
  pgbench -n -c 4 -j 4 -T "$DURATION" -f "$here/lock.sql" > /dev/null
  wait "$holder"
}

phase_io() {
  say "io: 8 sessions x commit-per-row for ${DURATION}s (expect IO:WALSync / LWLock:WALWrite)"
  pgbench -n -c 8 -j 8 -T "$DURATION" -f "$here/io.sql" > /dev/null
}

phases=("${@:-cpu lock io}")
read -r -a phases <<< "${phases[*]}"
for i in "${!phases[@]}"; do
  (( i > 0 )) && { say "pause ${GAP}s"; sleep "$GAP"; }
  "phase_${phases[$i]}"
done
say "done. Reset with: \\i sql/00b_reset.sql"
