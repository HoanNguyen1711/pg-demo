-- pgbench script, phase "lock": every client updates the same row that another session
-- already holds -> Lock:transactionid (first waiter) and Lock:tuple (the rest of the queue).
UPDATE orders SET note = 'pi-lock' WHERE id = 1;
