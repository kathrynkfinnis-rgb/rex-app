-- Run in Supabase Dashboard → SQL Editor → New query → Run.
--
-- Lets a "want to try" carry a note — why you want to go, who told you about
-- it — so it can appear in the feed as something friends can respond to,
-- rather than a bare title on a private list.
alter table public.wants
  add column if not exists note text;
