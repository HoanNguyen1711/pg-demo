-- 10_wait_events_optional.sql  (slide 23, Performance Insights; RDS only)
-- What Performance Insights samples once per second: active sessions and what they wait on.
--
-- ---------- Before the talk ----------
--   Open the RDS console -> pg-demo -> Monitoring -> Database Insights / Performance Insights,
--   chart "DB load" sliced by wait events, last 15 minutes. Keep the tab open.
--   Run 00b_reset.sql so the chart is quiet when you start.
--
-- ---------- On stage: three terminals ----------
--   T1  the SSM tunnel (already open).
--   T2  load generator, one phase at a time while you talk (60 s each, DURATION=90 to stretch):
--         sql/pi/load.sh cpu     6 sessions x the slide-4 Seq Scan on 2 vCPUs
--         sql/pi/load.sh lock    1 session holds row id = 1, 4 sessions try to update it
--         sql/pi/load.sh io      8 sessions commit one row at a time
--       or sql/pi/load.sh        all three, 30 s pause between (GAP=...)
--   T3  psql: \i sql/10_wait_events_optional.sql   (this file; Ctrl+C stops \watch)
--
-- ---------- What to point at ----------
--   cpu   T3: CPU | CPU | 6.        Chart: green CPU band above the "Max vCPU" line (2).
--         "Load 6 on 2 vCPUs: queries queue for CPU. Fix the query (slide 4), not the instance."
--   lock  T3: Lock | tuple | 3, Lock | transactionid | 1, Timeout | PgSleep | 1 (the holder).
--         Run the blocking query at the bottom of this file: blocked_by shows the holder's pid.
--         "One transaction left open, four sessions stuck. Same kind of session as slide 20."
--   io    T3: LWLock | WALWrite | ~7, IO | WALSync | ~1.
--         "Every COMMIT waits for the WAL flush. Commit in batches, not row by row."
--   Then scroll to "Top SQL" below the chart: the query behind each wait (ties to slide 22).
--   The chart lags the live query by a few seconds and averages per minute in longer views.
--
-- ---------- After ----------
--   \i sql/00b_reset.sql   (lock and io phases write to orders.note)

SELECT coalesce(wait_event_type, 'CPU') AS wait_type,
       coalesce(wait_event, 'CPU')      AS wait_event,
       count(*)                          AS sessions,
       left(regexp_replace(min(query), '\s+', ' ', 'g'), 60) AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND state = 'active'
  AND pid <> pg_backend_pid()
GROUP BY 1, 2
ORDER BY 3 DESC \watch 1

-- Lock phase: who blocks whom.
-- SELECT pid, pg_blocking_pids(pid) AS blocked_by, wait_event_type, wait_event,
--        left(query, 50) AS query
-- FROM pg_stat_activity
-- WHERE cardinality(pg_blocking_pids(pid)) > 0;
