-- Oct 3 — "The Place page: please can we pull photos from Google? ... It
-- would also be good to include: rex'd by x number of people; a summary of
-- what it is ie smash burgers, tacos, coffee; opening times."
--
-- The photos, the one-line summary and the opening hours all come from the
-- same Google Place Details call, and all three are billed. The field mask we
-- need spans three SKUs (Essentials for photos, Pro for the type name,
-- Enterprise for opening hours and the editorial summary), so a page that
-- fetched on every view would bill three times every time anybody opened a
-- place — and the same place over and over.
--
-- These columns make it once per place instead. The app fetches only when
-- details_fetched_at is null or long stale, writes the answer here, and every
-- later view of that place by anybody reads these columns for nothing. A few
-- hundred places against 10,000 free calls per SKU per month means this stays
-- inside the free tier rather than becoming a running cost.
--
-- Nullable throughout: a place typed in by hand has no Google id and will
-- never fill these in, and that has to render perfectly well.
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS summary text,
  ADD COLUMN IF NOT EXISTS opening_hours jsonb,
  ADD COLUMN IF NOT EXISTS google_photo_urls text[],
  ADD COLUMN IF NOT EXISTS details_fetched_at timestamptz;

COMMENT ON COLUMN public.items.summary IS
  'One line saying what the place is ("smash burgers"), from Google''s editorial summary or its primary type.';
COMMENT ON COLUMN public.items.opening_hours IS
  'Google regularOpeningHours.weekdayDescriptions, stored as a JSON array of seven strings.';
COMMENT ON COLUMN public.items.google_photo_urls IS
  'Places photo media URLs. Must be rendered through GoogleSafeAsyncImage — a plain request has no bundle header and silently returns nothing.';
COMMENT ON COLUMN public.items.details_fetched_at IS
  'When Place Details was last fetched. Null means never; the app refetches only when this is older than 90 days.';

-- Nothing here is per-user, so it rides on the existing items policies:
-- readable by everyone who can read the item, writable by any signed-in user
-- (same as the rest of the catalogue).
