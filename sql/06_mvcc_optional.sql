-- 06_mvcc_optional.sql  (slide 17)
-- UPDATE does not overwrite: watch xmin, xmax and ctid.
-- To rerun, change the id (e.g. 2, 3, ...) everywhere below.

SELECT xmin, xmax, ctid, status FROM orders WHERE id = 1;
-- Remember the page (block) and slot of the current version.
SELECT (ctid::text::point)[0]::int AS blk, (ctid::text::point)[1]::int AS lp
FROM orders WHERE id = 1 \gset

BEGIN;
SELECT txid_current();             -- this txid becomes xmax of the old version and xmin of the new one
UPDATE orders SET status = 'paid' WHERE id = 1;

-- Inside the heap page, before COMMIT (pageinspect; on RDS this may need superuser,
-- if you get "permission denied", skip this query: the rest of the demo still works): the old version is still there,
-- with t_xmax = our txid and t_ctid pointing to the new version.
SELECT lp, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('orders', :blk))
WHERE lp = :lp;
COMMIT;

-- After COMMIT: new xmin, new ctid (the row lives at a new physical location).
SELECT xmin, xmax, ctid, status FROM orders WHERE id = 1;

-- Two-session demo: readers do not block writers.
--   Session A:  BEGIN ISOLATION LEVEL REPEATABLE READ;
--               SELECT status FROM orders WHERE id = 2;      -- 'completed' (or whatever it is)
--   Session B:  UPDATE orders SET status = 'paid' WHERE id = 2;   -- returns at once
--   Session A:  SELECT status FROM orders WHERE id = 2;      -- still the old value
--               COMMIT;
--               SELECT status FROM orders WHERE id = 2;      -- now 'paid'
