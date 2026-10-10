-- pgbench script, phase "cpu": the slide-4 query (cast on the column -> Seq Scan over 10M rows).
-- Data is cached, so the time is pure CPU. 6 clients on 2 vCPUs -> load above the Max vCPU line.
SET max_parallel_workers_per_gather = 0;
SELECT count(*) FROM orders WHERE created_at::date = '2026-10-01';
