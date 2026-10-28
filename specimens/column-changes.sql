-- Project-owned order-service rollout: constant/stable/volatile defaults differ.
-- This tool reviews the file; it never executes the following SQL.
SET lock_timeout = '1s';
SET statement_timeout = '30s';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending' NOT NULL;
ALTER TABLE orders ADD COLUMN received_at timestamptz DEFAULT now();
ALTER TABLE orders ADD COLUMN recorded_at timestamptz DEFAULT clock_timestamp();
ALTER TABLE orders ALTER COLUMN amount TYPE numeric(12,2) USING amount::numeric(12,2);
ALTER TABLE orders ALTER COLUMN recorded_at SET DEFAULT now();
