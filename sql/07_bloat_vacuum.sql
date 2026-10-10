-- 07_bloat_vacuum.sql  (slides 18-19)
-- Uses a 1M-row copy so each UPDATE finishes in a few seconds on stage.
-- Runs in psql and in DBeaver. In DBeaver, skip the \timing line (psql only);
-- DBeaver shows the execution time of each statement itself.
\timing on

DROP TABLE IF EXISTS orders_bloat;
CREATE TABLE orders_bloat AS SELECT * FROM orders WHERE id <= 1000000;
ALTER TABLE orders_bloat SET (autovacuum_enabled = off);
VACUUM ANALYZE orders_bloat;

-- The same stats query after every step. pgstattuple reads the table itself, so the
-- numbers are exact right after each statement (no stats-collector delay) and it works on RDS too.

-- Initial
SELECT tuple_count AS live_rows, dead_tuple_count AS dead_rows, pg_size_pretty(table_len) AS size
FROM pgstattuple('orders_bloat');

-- UPDATE 1: every row gets a new version. Size roughly doubles.
UPDATE orders_bloat SET amount = amount;
SELECT tuple_count AS live_rows, dead_tuple_count AS dead_rows, pg_size_pretty(table_len) AS size
FROM pgstattuple('orders_bloat');

-- UPDATE 2: grows again.
UPDATE orders_bloat SET amount = amount;
SELECT tuple_count AS live_rows, dead_tuple_count AS dead_rows, pg_size_pretty(table_len) AS size
FROM pgstattuple('orders_bloat');

-- VACUUM removes dead tuples, but the file does not shrink.
VACUUM orders_bloat;
SELECT tuple_count AS live_rows, dead_tuple_count AS dead_rows, pg_size_pretty(table_len) AS size
FROM pgstattuple('orders_bloat');

-- ...and the freed space is reused: this UPDATE does not grow the table.
UPDATE orders_bloat SET amount = amount;
SELECT tuple_count AS live_rows, dead_tuple_count AS dead_rows, pg_size_pretty(table_len) AS size
FROM pgstattuple('orders_bloat');

-- VACUUM FULL rewrites the table and returns space to the OS (ACCESS EXCLUSIVE lock).
VACUUM FULL orders_bloat;
SELECT tuple_count AS live_rows, dead_tuple_count AS dead_rows, pg_size_pretty(table_len) AS size


select * FROM pgstattuple('orders_bloat');
