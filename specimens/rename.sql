-- Project-owned rolling-release example; review application cutover separately.
SET lock_timeout = '1s';
BEGIN;
ALTER TABLE orders RENAME COLUMN legacy_reference TO external_reference;
ALTER TABLE orders RENAME CONSTRAINT orders_customer_fk TO purchases_customer_fk;
ALTER TABLE orders RENAME TO purchases;
ALTER TABLE purchases VALIDATE CONSTRAINT purchases_customer_fk;
COMMIT;
ALTER INDEX orders_created_at_idx RENAME TO purchases_created_at_idx;
