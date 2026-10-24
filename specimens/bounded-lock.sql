-- Submit each statement separately on the same session, without an outer transaction.
SET SESSION lock_timeout = '1s';
SET SESSION statement_timeout = '30s';
CREATE INDEX CONCURRENTLY customer_created_at_idx
ON public.customers (created_at);
