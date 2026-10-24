SET lock_timeout = '2s';
BEGIN;
SAVEPOINT budget_trial;
SET LOCAL lock_timeout = '100ms';
CREATE INDEX trial_idx ON public.orders (customer_id);
ROLLBACK TO SAVEPOINT budget_trial;
-- The index and its local budget were rolled back; 2s is effective again.
CREATE INDEX orders_customer_idx ON public.orders (customer_id);
RELEASE SAVEPOINT budget_trial;
COMMIT;
