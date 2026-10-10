-- 03_composite_optional.sql  (slide 11)
-- Column order in a composite index.
\timing on
SET max_parallel_workers_per_gather = 0;
SET jit = off;   -- hide JIT lines from EXPLAIN output

CREATE INDEX IF NOT EXISTS idx_orders_cust_date ON orders (customer_id, created_at);
ANALYZE orders;

-- Leading column -> uses the index.
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customer_id = 42;

-- Both columns -> uses the index, both in Index Cond.
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customer_id = 42 AND created_at >= '2026-10-01';

-- Only the second column. idx_orders_created would answer this, so drop it
-- inside a transaction and roll back afterwards (DDL is transactional in Postgres).
BEGIN;
DROP INDEX idx_orders_created;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE created_at >= '2026-10-01';
ROLLBACK;

RESET max_parallel_workers_per_gather;
