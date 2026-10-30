-- Project-owned example: commit schema expansion before long-running batches.
SET lock_timeout = '1s';
SET statement_timeout = '30s';
BEGIN;
ALTER TABLE orders ADD COLUMN status text;
WITH batch AS (
  SELECT id FROM orders WHERE status IS NULL ORDER BY id LIMIT 100
  FOR UPDATE SKIP LOCKED
)
UPDATE orders o SET status = 'pending' FROM batch b WHERE o.id = b.id;
COMMIT;
DELETE FROM retired_orders WHERE id < 1000 RETURNING id;
