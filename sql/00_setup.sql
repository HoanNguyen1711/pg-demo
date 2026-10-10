-- 00_setup.sql
-- Build the demo data. Run once before the talk (takes a few minutes for 10M rows).
--   docker compose exec db psql -U postgres -f /demo/00_setup.sql
-- For a quick test run, lower the row count:  psql ... -v rows=1000000 -f ...

\if :{?rows}
\else
  \set rows 10000000
\endif
\timing on

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE EXTENSION IF NOT EXISTS pgstattuple;

DROP TABLE IF EXISTS orders_bloat;
DROP TABLE IF EXISTS orders_stage;
DROP TABLE IF EXISTS orders_by_time;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;

-- 1M customers. Half the emails are stored with a capital letter, which is why
-- the application queries them with lower(email).
CREATE TABLE customers (
    id    int  PRIMARY KEY,
    email text NOT NULL
);

INSERT INTO customers (id, email)
SELECT g,
       CASE WHEN g % 2 = 0 THEN 'User' ELSE 'user' END
       || g || '@'
       || (ARRAY['gmail.com', 'yahoo.com', 'outlook.com', 'company.vn'])[1 + g % 4]
FROM generate_series(1, 1000000) AS g;

CREATE INDEX idx_customers_email ON customers (email);

-- Orders. Status distribution is skewed on purpose:
--   completed ~90%, shipped ~5%, cancelled ~3.9%, pending ~1%, refunded ~0.1%
-- created_at is spread over two years ending 2026-10-10.
CREATE TABLE orders (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id int           NOT NULL,
    status      text          NOT NULL,
    amount      numeric(12,2) NOT NULL,
    created_at  timestamp     NOT NULL,
    note        text
);

INSERT INTO orders (customer_id, status, amount, created_at)
SELECT 1 + (random() * 999999)::int,
       CASE
           WHEN r < 0.001 THEN 'refunded'
           WHEN r < 0.011 THEN 'pending'
           WHEN r < 0.050 THEN 'cancelled'
           WHEN r < 0.100 THEN 'shipped'
           ELSE 'completed'
       END,
       round((random() * 500)::numeric, 2),
       timestamp '2024-10-10' + random() * interval '730 days'
FROM (SELECT random() AS r FROM generate_series(1, :rows)) AS s;

-- Customer 42 is the one used on the slides: give it a steady order history
-- up to October 2026 so every demo query returns rows.
INSERT INTO orders (customer_id, status, amount, created_at)
SELECT 42, 'completed', round((random() * 500)::numeric, 2),
       timestamp '2025-11-05 10:00' + g * interval '28 days'
FROM generate_series(1, 12) AS g;

-- The only secondary index at the start, matching slide 4.
CREATE INDEX idx_orders_created ON orders (created_at);

-- VACUUM sets the visibility map (needed for Index Only Scan later), ANALYZE fills pg_stats.
VACUUM ANALYZE customers;
VACUUM ANALYZE orders;

-- Same rows stored in created_at order, for the BRIN demo (05b_brin.sql). ~15 s.
CREATE TABLE orders_by_time AS SELECT * FROM orders ORDER BY created_at;
VACUUM ANALYZE orders_by_time;

SELECT status, count(*), round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM orders GROUP BY status ORDER BY 2 DESC;

SELECT pg_size_pretty(pg_relation_size('orders'))          AS orders_heap,
       pg_size_pretty(pg_relation_size('idx_orders_created')) AS idx_orders_created;
