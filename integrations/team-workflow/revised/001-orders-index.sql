-- Reviewed alternative: runner must use autocommit, one statement at a time.
CREATE INDEX CONCURRENTLY orders_customer_idx ON public.orders(customer_id);
