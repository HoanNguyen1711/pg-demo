-- 05b_brin.sql  (slide 15)
-- BRIN stores only the min/max of each block range: tiny, but useful only when the
-- physical row order follows the column (append-only logs, events, time series).
\timing on
SET max_parallel_workers_per_gather = 0;
SET jit = off;   -- hide JIT lines from EXPLAIN output

-- orders_by_time is a copy of orders sorted by created_at, built and analyzed by
-- 00_setup.sql. If it is missing, this builds it (~15 s); then run ANALYZE orders_by_time.
CREATE TABLE IF NOT EXISTS orders_by_time AS SELECT * FROM orders ORDER BY created_at;

CREATE INDEX idx_orders_brin ON orders USING brin (created_at);
CREATE INDEX idx_orders_by_time_brin ON orders_by_time USING brin (created_at);

-- Size: B-tree vs BRIN on the same 10M rows.
SELECT 'B-tree (idx_orders_created)' AS index, pg_size_pretty(pg_relation_size('idx_orders_created')) AS size
UNION ALL
SELECT 'BRIN (idx_orders_brin)',             pg_size_pretty(pg_relation_size('idx_orders_brin'));

-- The twist: orders was generated with random created_at, so every block range
-- covers the whole two years. Hide the B-tree: the planner picks either the new BRIN
-- index or a Seq Scan (a close call that depends on the ANALYZE sample). Either way
-- ~1.3 s, as slow as reading the whole table.
BEGIN;
DROP INDEX idx_orders_created;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders
WHERE created_at >= '2026-10-01' AND created_at < '2026-10-02';

-- Force BRIN to see why. Point at: "Heap Blocks: lossy=84558" (every block of the
-- table) and "Rows Removed by Index Recheck: ~10M".
SET LOCAL enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders
WHERE created_at >= '2026-10-01' AND created_at < '2026-10-02';
ROLLBACK;

-- Why: correlation between physical order and created_at.
SELECT tablename, round(correlation::numeric, 3) AS correlation
FROM pg_stats
WHERE attname = 'created_at' AND tablename IN ('orders', 'orders_by_time');

-- Same data, stored in time order: BRIN skips almost everything.
-- Point at: "Heap Blocks: lossy=256" and the execution time.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders_by_time
WHERE created_at >= '2026-10-01' AND created_at < '2026-10-02';

RESET max_parallel_workers_per_gather;
