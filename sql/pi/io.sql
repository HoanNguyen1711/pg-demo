-- pgbench script, phase "io": many tiny transactions, each COMMIT waits for the WAL to be
-- flushed to disk -> IO:WALSync / LWLock:WALWrite (the classic "commit too often" pattern,
-- e.g. an ETL job that commits row by row). The loop runs on the server, so the tunnel's
-- latency does not matter. 00b_reset.sql clears the notes afterwards.
DO $$
DECLARE
    target bigint;
BEGIN
    FOR i IN 1..500 LOOP
        -- Pick the id first: random() inside WHERE is re-evaluated for every row -> Seq Scan.
        target := 1 + (random() * 9999999)::bigint;
        UPDATE orders SET note = 'pi-wal' WHERE id = target;
        COMMIT;
    END LOOP;
END $$;
