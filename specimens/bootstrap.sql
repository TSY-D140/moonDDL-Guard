-- A new child relation and repeatable application seed rows.
-- Verify the existing parent key and schedule its referenced-table lock.
SET lock_timeout='1s';
SET statement_timeout='30s';
CREATE TABLE IF NOT EXISTS public.order_status (
  id int PRIMARY KEY,
  label text NOT NULL DEFAULT 'pending',
  parent_id int REFERENCES public.parent(id)
);
INSERT INTO public.order_status(id,label) VALUES (1,'pending'),(2,'paid')
ON CONFLICT(id) DO NOTHING RETURNING id;
INSERT INTO public.order_status(id,label) VALUES (2,'settled')
ON CONFLICT(id) DO UPDATE SET label=excluded.label;
