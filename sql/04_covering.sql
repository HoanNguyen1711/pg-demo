-- 04_covering.sql  (slides 13 and 16)
-- Covering index with INCLUDE -> Index Only Scan.
\timing on
SET max_parallel_workers_per_gather = 0;
SET jit = off;   -- hide JIT lines from EXPLAIN output

-- Before: every matching row is read from the heap (Seq Scan, or Index Scan on
-- idx_orders_cust_date if 03_composite_optional.sql ran first).
CREATE INDEX IF NOT EXISTS idx_orders_cust_date ON orders (customer_id, created_at);
ANALYZE orders;

EXPLAIN (ANALYZE, BUFFERS)
SELECT amount, status FROM orders WHERE customer_id = 42;

CREATE INDEX idx_cust_cover ON orders (customer_id) INCLUDE (amount, status);
VACUUM ANALYZE orders;   -- make sure the visibility map is up to date

-- After: Index Only Scan, Heap Fetches: 0.
EXPLAIN (ANALYZE, BUFFERS)
SELECT amount, status FROM orders WHERE customer_id = 42;

-- A wider range makes the next step easier to see.
EXPLAIN (ANALYZE, BUFFERS)
SELECT amount, status FROM orders WHERE customer_id BETWEEN 1 AND 1000;

-- Bulk UPDATE, then run the same query again.
UPDATE orders SET note = 'touched' WHERE customer_id BETWEEN 1 AND 1000;

EXPLAIN (ANALYZE, BUFFERS)
SELECT amount, status FROM orders WHERE customer_id BETWEEN 1 AND 1000;
-- -> still Index Only Scan, but Heap Fetches jumps. Why? (MVCC, next section)

-- Payoff after the MVCC section: VACUUM sets the visibility map again.
VACUUM orders;
EXPLAIN (ANALYZE, BUFFERS)
SELECT amount, status FROM orders WHERE customer_id BETWEEN 1 AND 1000;

RESET max_parallel_workers_per_gather;
