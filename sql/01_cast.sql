-- 01_cast.sql 
-- "What is wrong with this query?"
\timing on
-- Keep plans simple to read on screen: no parallel workers.
SET max_parallel_workers_per_gather = 0;
SET jit = off;  

-- Cast on the column -> Seq Scan, the cast runs for every row.
-- Point at: "Seq Scan", "Filter: ((created_at)::date = ...)", "Rows Removed by Filter".
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE created_at::date = '2026-10-01';

-- Same result, written as a range -> Index Scan, "Index Cond".
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE created_at >= '2026-10-01' AND created_at < '2026-10-02';

-- Check both return the same number of rows.
SELECT count(*) FROM orders WHERE created_at::date = '2026-10-01';
SELECT count(*) FROM orders WHERE created_at >= '2026-10-01' AND created_at < '2026-10-02';

-- Function on the column.
EXPLAIN ANALYZE
SELECT * FROM customers WHERE lower(email) = 'user42@outlook.com';

CREATE INDEX idx_customers_email_lower ON customers (lower(email));

EXPLAIN ANALYZE
SELECT * FROM customers WHERE lower(email) = 'user42@outlook.com';

-- 123.0 is numeric, so Postgres casts the column: (id)::numeric = 123.0 -> Seq Scan.
EXPLAIN ANALYZE SELECT * FROM orders WHERE id = 123.0;
EXPLAIN ANALYZE SELECT * FROM orders WHERE id = 123;

-- Leading wildcard. A B-tree cannot help.
EXPLAIN ANALYZE
SELECT * FROM customers WHERE email LIKE '%4242@outlook.com';

CREATE INDEX idx_customers_email_trgm ON customers USING gin (email gin_trgm_ops);

EXPLAIN ANALYZE
SELECT * FROM customers WHERE email LIKE '%4242@outlook.com';

RESET max_parallel_workers_per_gather;
