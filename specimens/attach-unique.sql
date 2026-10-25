SET lock_timeout = '1s';
CREATE UNIQUE INDEX CONCURRENTLY users_email_candidate ON public.users (email);
-- Independently inspect index validity/eligibility and data before cutover.
ALTER TABLE public.users ADD CONSTRAINT users_email_key UNIQUE USING INDEX users_email_candidate;
