-- Extend an existing application's status type, committing before writers use it.
SET lock_timeout='1s';
SET statement_timeout='30s';
BEGIN;
ALTER TYPE public.delivery_status ADD VALUE IF NOT EXISTS 'queued' BEFORE 'paid';
COMMIT;
INSERT INTO public.order_status(id,label) VALUES(3,'queued') ON CONFLICT(id) DO NOTHING;
-- A separate coordinated cutover; old textual values will no longer work.
ALTER TYPE public.delivery_status RENAME VALUE 'pending' TO 'awaiting_payment';
