SET lock_timeout = '1s';
ALTER TABLE public.users ADD CONSTRAINT users_email_present CHECK (email IS NOT NULL) NOT VALID;
-- Submit phases separately and inspect target metadata/data before cutover.
ALTER TABLE public.users VALIDATE CONSTRAINT users_email_present;
ALTER TABLE public.users ALTER COLUMN email SET NOT NULL;
