-- Run this in the Supabase Dashboard → SQL Editor → New query → Run.
--
-- Adds three columns. Together they unblock:
--   * trip import with section headings (raw_section)
--   * hyperlinks captured during import (raw_url)
--   * product links / hyperlinks on any item (items.link_url)
--
-- Safe to re-run: every statement uses IF NOT EXISTS.

-- 1. Carry a heading (e.g. "Brunch", "Museums") through the import queue so
--    imported trip stops land under the right section.
alter table public.import_staging
  add column if not exists raw_section text;

-- 2. Carry a URL found next to an item in the imported document.
alter table public.import_staging
  add column if not exists raw_url text;

-- 3. A link on the item itself — used for the "Product link" field on Stuff,
--    and for hyperlinks generally.
alter table public.items
  add column if not exists link_url text;
