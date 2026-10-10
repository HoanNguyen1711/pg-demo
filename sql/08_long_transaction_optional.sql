-- 08_long_transaction_optional.sql  (slide 20)
-- Needs TWO psql sessions. Run 07_bloat_vacuum.sql first (it creates orders_bloat).
--
-- ---------- Session A ----------
--   BEGIN ISOLATION LEVEL REPEATABLE READ;
--   SELECT count(*) FROM orders_bloat;     -- takes a snapshot, then leave it open
--
-- ---------- Session B: run this file ----------

UPDATE orders_bloat SET amount = amount WHERE id <= 100000;

-- Look for: "100000 are dead but not yet removable"
VACUUM (VERBOSE) orders_bloat;

-- Who is holding it back?
SELECT pid, state, backend_xmin,
       now() - xact_start AS xact_age,
       left(query, 60)    AS query
FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL AND pid <> pg_backend_pid()
ORDER BY xact_start;

-- ---------- Session A ----------
--   COMMIT;
--
-- ---------- Session B ----------
--   VACUUM (VERBOSE) orders_bloat;          -- now the 100000 tuples are removed
