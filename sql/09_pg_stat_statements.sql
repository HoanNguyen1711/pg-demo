-- 09_pg_stat_statements.sql 
-- Step 1 "Find": which queries cost the most in total?
-- Reset before the talk so the list only shows the demo queries:
--   SELECT pg_stat_statements_reset();

SELECT calls,
       round(total_exec_time::numeric, 1)            AS total_ms,
       round(mean_exec_time::numeric, 2)             AS mean_ms,
       rows,
       shared_blks_hit + shared_blks_read            AS blocks,
       left(regexp_replace(query, '\s+', ' ', 'g'), 80) AS query
FROM pg_stat_statements
WHERE query NOT ILIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 10;
