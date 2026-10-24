SET lock_timeout = '1s';
CREATE INDEX CONCURRENTLY orders_customer_created_idx ON public.orders (customer_id, created_at);
-- Verify the new index's catalog validity and query coverage before the drop.
DROP INDEX CONCURRENTLY IF EXISTS public.orders_customer_idx;
