BEGIN;
CREATE INDEX CONCURRENTLY orders_customer_idx ON orders (customer_id);
ROLLBACK;
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS customers_email_idx ON customers (email);
