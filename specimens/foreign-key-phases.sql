-- Project-owned example. Existing orders.customer_id references customers.id.
-- Send statements separately in autocommit; verify the actual schema and data.
SET lock_timeout = '1s';
SET statement_timeout = '30s';
ALTER TABLE orders ADD CONSTRAINT orders_customer_fk
  FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_fk;
