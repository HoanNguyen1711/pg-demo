-- 00b_reset.sql
-- Put the database back to the state right after 00_setup.sql, without reloading 10M rows.
-- Run before each rehearsal and once more right before the talk (takes a few seconds).
-- No psql meta-commands, so it also runs as a script in DBeaver.

-- 08: a forgotten "Session A" holds back VACUUM. End any idle open transaction.
SELECT pid, pg_terminate_backend(pid) AS terminated
FROM pg_stat_activity
WHERE datname = current_database()
  AND state LIKE 'idle in transaction%'
  AND pid <> pg_backend_pid();

-- 02b, 07: demo tables.
DROP TABLE IF EXISTS w_noidx;
DROP TABLE IF EXISTS w_5idx;
DROP TABLE IF EXISTS orders_bloat;
-- 02c: staging table.
DROP TABLE IF EXISTS orders_stage;

-- 01, 02, 03, 04, 05, 05b (and anything created during Q&A): drop every index on
-- orders/customers/orders_by_time except the primary keys and the two indexes from 00_setup.sql.
DO $$
DECLARE
    idx record;
BEGIN
    FOR idx IN
        SELECT i.indexrelid::regclass AS name
        FROM pg_index i
        WHERE i.indrelid IN ('orders'::regclass, 'customers'::regclass, to_regclass('orders_by_time'))
          AND NOT i.indisprimary
          AND i.indexrelid::regclass::text NOT IN ('idx_orders_created', 'idx_customers_email')
    LOOP
        RAISE NOTICE 'dropping index %', idx.name;
        EXECUTE format('DROP INDEX %s', idx.name);
    END LOOP;
END $$;

-- 04: the bulk UPDATE set note = 'touched' (note is NULL after setup).
UPDATE orders SET note = NULL WHERE note IS NOT NULL;

-- 06: the UPDATEs set status = 'paid', a value setup never generates.
-- The original value is not kept; 'completed' is what ~90% of rows have.
UPDATE orders SET status = 'completed' WHERE status = 'paid';

-- Remove the dead tuples from the two UPDATEs, set the visibility map again
-- (04 needs "Heap Fetches: 0") and refresh pg_stats (02 shows most_common_vals).
VACUUM ANALYZE orders;
VACUUM ANALYZE customers;

-- 02 footer (unused indexes) and 09 (top queries) should only show the talk's queries.
SELECT pg_stat_reset();
SELECT pg_stat_statements_reset();

-- Load the tables into shared_buffers so the first demo is not slower than the rest.
CREATE EXTENSION IF NOT EXISTS pg_prewarm;
SELECT pg_prewarm('orders') AS orders_blocks,
       pg_prewarm('idx_orders_created') AS idx_blocks,
       pg_prewarm('customers') AS customers_blocks,
       pg_prewarm('orders_by_time') AS orders_by_time_blocks;

-- Check: only the setup indexes remain, no dead rows.
SELECT c.relname AS table_name, i.indexrelid::regclass AS index_name,
       pg_size_pretty(pg_relation_size(i.indexrelid)) AS size
FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
WHERE c.relname IN ('orders', 'customers')
ORDER BY 1, 2;
