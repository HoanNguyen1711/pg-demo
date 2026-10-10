-- 02b_write_cost_optional.sql  (slide 8, optional)
-- Same 1M-row insert into a table with no secondary index and with five.
\timing on

DROP TABLE IF EXISTS w_noidx;
DROP TABLE IF EXISTS w_5idx;
CREATE TABLE w_noidx (LIKE orders INCLUDING IDENTITY);
CREATE TABLE w_5idx  (LIKE orders INCLUDING IDENTITY);

CREATE INDEX ON w_5idx (customer_id);
CREATE INDEX ON w_5idx (status);
CREATE INDEX ON w_5idx (created_at);
CREATE INDEX ON w_5idx (amount);
CREATE INDEX ON w_5idx (customer_id, created_at);

-- Compare the two "Time:" lines.
INSERT INTO w_noidx (customer_id, status, amount, created_at)
SELECT customer_id, status, amount, created_at FROM orders WHERE id <= 1000000;

INSERT INTO w_5idx (customer_id, status, amount, created_at)
SELECT customer_id, status, amount, created_at FROM orders WHERE id <= 1000000;

SELECT 'no index' AS t, pg_size_pretty(pg_total_relation_size('w_noidx')) AS total_size
UNION ALL
SELECT '5 indexes', pg_size_pretty(pg_total_relation_size('w_5idx'));

DROP TABLE w_noidx;
DROP TABLE w_5idx;
