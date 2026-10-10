-- 02c_stale_stats.sql  (slide 10)
-- After a bulk load, the statistics still describe yesterday's data: the planner
-- expects 1 row, gets 500,000, and picks the wrong plan. ANALYZE fixes it.
\timing on
SET max_parallel_workers_per_gather = 0;
SET jit = off;   -- hide JIT lines from EXPLAIN output

-- A staging table, loaded once a day. Autovacuum would ANALYZE it eventually, but not
-- before the next ETL step runs; it is off here so the demo behaves the same every time.
DROP TABLE IF EXISTS orders_stage;
CREATE TABLE orders_stage (
    order_id    bigint,
    customer_id int,
    amount      numeric(12,2),
    batch_date  date
) WITH (autovacuum_enabled = off);

-- Yesterday's batch, analyzed by the nightly job.
INSERT INTO orders_stage
SELECT id, customer_id, amount, date '2026-10-08' FROM orders WHERE id <= 500000;
ANALYZE orders_stage;

-- Today's batch, just loaded. No ANALYZE yet.
INSERT INTO orders_stage
SELECT id, customer_id, amount, date '2026-10-09' FROM orders WHERE id > 500000 AND id <= 1000000;

-- What the planner believes about today's batch: pg_stats only knows 2026-10-08.
SELECT most_common_vals, most_common_freqs
FROM pg_stats
WHERE tablename = 'orders_stage' AND attname = 'batch_date';

-- Point at: "rows=1" (estimate) vs "rows=500000" (actual).
EXPLAIN (ANALYZE, TIMING OFF)
SELECT count(*) FROM orders_stage WHERE batch_date = '2026-10-09';

-- The next ETL step: top customers in today's batch.
-- Stale stats -> Nested Loop with 500,000 index lookups, then Sort + GroupAggregate.
EXPLAIN (ANALYZE)
SELECT c.email, sum(s.amount) AS total
FROM orders_stage s
JOIN customers c ON c.id = s.customer_id
WHERE s.batch_date = '2026-10-09'
GROUP BY c.email
ORDER BY total DESC
LIMIT 5;

-- The fix takes a fraction of a second.
ANALYZE orders_stage;

-- Same query: estimate ~500,000 rows -> Hash Join + HashAggregate, about 3.5 times faster.
EXPLAIN (ANALYZE)
SELECT c.email, sum(s.amount) AS total
FROM orders_stage s
JOIN customers c ON c.id = s.customer_id
WHERE s.batch_date = '2026-10-09'
GROUP BY c.email
ORDER BY total DESC
LIMIT 5;

RESET max_parallel_workers_per_gather;
