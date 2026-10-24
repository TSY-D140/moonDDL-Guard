SET lock_timeout = '2s';
BEGIN;
SET LOCAL lock_timeout = '100ms';
CREATE INDEX customer_email_idx ON public.customers (email);
ROLLBACK;
-- The transaction-local 100ms budget has expired; the session's 2s returns.
CREATE INDEX CONCURRENTLY customer_email_idx ON public.customers (email);
