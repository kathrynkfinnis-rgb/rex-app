-- #102 (Phoebe): onboarding asks new users what they're interested in, so
-- there's somewhere to persist the answer. Nothing reads this yet (the
-- onboarding screen is the only writer for now) - it's captured so it's
-- available for feed personalization later without a second migration.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS interests text[];
