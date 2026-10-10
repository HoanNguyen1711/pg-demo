-- 02_selectivity_optional.sql  (slides 8-9)
-- "Is adding an index enough?"
\timing on
SET max_parallel_workers_per_gather = 0;
SET jit = off;   -- hide JIT lines from EXPLAIN output

CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
ANALYZE orders;

-- Slide 9: what the planner knows about status.
SELECT most_common_vals, most_common_freqs
FROM pg_stats
WHERE tablename = 'orders' AND attname = 'status';

-- Rare value (~0.1%) -> the index is used.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'refunded';

-- Common value (~90%) -> same index, same query, Seq Scan.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'completed';

-- Optional: force the index to show it would be slower.
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'completed';
RESET enable_seqscan;

-- Slide 8 footer: find indexes nobody uses.
SELECT relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
ORDER BY idx_scan, pg_relation_size(indexrelid) DESC;

RESET max_parallel_workers_per_gather;
