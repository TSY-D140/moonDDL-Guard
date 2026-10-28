-- Project-owned cleanup examples: inspect dependencies and backups first.
-- Targets are illustrative existing objects; nothing is executed by the reviewer.
SET lock_timeout = '1s';
ALTER TABLE orders DROP COLUMN IF EXISTS legacy_reference RESTRICT;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_customer_fk;
DROP TABLE IF EXISTS retired_orders CASCADE;
TRUNCATE TABLE temporary_order_events RESTART IDENTITY CASCADE;
