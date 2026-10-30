-- Project-owned example: review direct blocking builds versus concurrent cutover.
SET lock_timeout = '1s';
ALTER TABLE orders ADD CONSTRAINT orders_reference_unique UNIQUE NULLS NOT DISTINCT (external_reference);
ALTER TABLE archived_orders ADD CONSTRAINT archived_orders_pk PRIMARY KEY (id);
