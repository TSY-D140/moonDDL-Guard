SET lock_timeout = '1s';
ALTER TABLE public.orders ADD CONSTRAINT orders_positive_amount CHECK (amount >= 0) NOT VALID;
-- End the ADD transaction before checking pre-existing rows.
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_positive_amount;
