-- Illustrative rollout for a populated orders table, using one runner session.
-- Ordinary additions share one statement and lock; volatile creation dominates
-- rewrite cost even when other columns have fast defaults.
SET lock_timeout = '1s';
SET statement_timeout = '30s';
BEGIN;
SAVEPOINT before_columns;
ALTER TABLE orders
  ADD COLUMN status text DEFAULT 'pending' NOT NULL,
  ADD COLUMN amount_copy numeric(12,2),
  ADD COLUMN changed_at timestamptz DEFAULT clock_timestamp();
UPDATE orders SET status = 'paid' WHERE id = 1;
ROLLBACK TO before_columns;
COMMIT;
