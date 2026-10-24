CREATE UNIQUE INDEX CONCURRENTLY active_customer_email_idx
ON public.customers USING btree (lower(email)) INCLUDE (customer_id)
WHERE deleted_at IS NULL;

CREATE INDEX customer_full_name_idx
ON public.customers ((first_name || ' ' || last_name));
