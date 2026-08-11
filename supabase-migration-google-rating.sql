-- Run in Supabase Dashboard → SQL Editor → New query → Run.
-- Stores Google's public rating alongside friends' ratings on places.
alter table public.items add column if not exists google_rating numeric;
alter table public.items add column if not exists google_rating_count integer;
