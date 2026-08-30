-- #182 — GDPR/privacy-policy consent on sign-up. Records when a user
-- explicitly agreed to the Terms of Use / Privacy Policy shown at sign-up
-- (LegalContentView), so there's a real, timestamped record of consent
-- rather than just the app trusting the checkbox was ticked.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS accepted_terms_at timestamptz;
