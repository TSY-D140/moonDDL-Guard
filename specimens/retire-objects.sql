-- Coordinate dependent applications, backups and grants before retiring objects.
SET lock_timeout='1s';
SET statement_timeout='30s';
DROP VIEW IF EXISTS public.old_orders RESTRICT;
DROP MATERIALIZED VIEW IF EXISTS public.monthly_sales;
DROP SEQUENCE IF EXISTS public.old_counter CASCADE;
DROP TYPE IF EXISTS public.old_state CASCADE;
DROP DOMAIN IF EXISTS public.legacy_amount RESTRICT;
DROP FUNCTION IF EXISTS public.old_format(integer,text) RESTRICT;
DROP PROCEDURE IF EXISTS public.old_refresh() RESTRICT;
BEGIN;
DROP TRIGGER IF EXISTS legacy_audit ON public.orders;
DROP POLICY IF EXISTS old_access ON public.orders CASCADE;
COMMIT;
DROP SCHEMA IF EXISTS archive CASCADE;
DROP EXTENSION IF EXISTS hstore RESTRICT;
