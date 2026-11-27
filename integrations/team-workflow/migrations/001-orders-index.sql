-- Illustrative order-service migration, Apache-2.0.
CREATE INDEX orders_customer_idx ON public.orders(customer_id);
