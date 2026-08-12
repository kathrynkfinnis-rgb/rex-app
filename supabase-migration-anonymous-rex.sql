-- Run in Supabase Dashboard → SQL Editor → New query → Run.
--
-- Lets a Rex be posted without your name on it. The row still belongs to you,
-- so it counts toward your profile and the leaderboard — only the display is
-- anonymous.
alter table public.recommendations
  add column if not exists is_anonymous boolean not null default false;
