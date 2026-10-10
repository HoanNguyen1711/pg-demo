-- 05_partial_optional.sql  (slide 14)
-- Partial index: only the ~1% pending rows.
\timing on
SET max_parallel_workers_per_gather = 0;
SET jit = off;   -- hide JIT lines from EXPLAIN output

CREATE INDEX idx_pending ON orders (created_at) WHERE status = 'pending';
ANALYZE orders;

-- Fill the size table on slide 14.
SELECT 'Full (idx_orders_created)' AS index, pg_size_pretty(pg_relation_size('idx_orders_created')) AS size
UNION ALL
SELECT 'Partial (idx_pending)',     pg_size_pretty(pg_relation_size('idx_pending'));

-- Condition matches the index WHERE clause -> idx_pending.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE status = 'pending' AND created_at >= '2026-09-01';

-- No status condition -> the planner cannot use idx_pending.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE created_at >= '2026-09-01' AND created_at < '2026-09-02';

RESET max_parallel_workers_per_gather;
