-- Oct 18 — "I'd like to be able to put friends collections into my topics."
--
-- A collection's `topic` lives on hitlist_lists and belongs to whoever owns
-- it. That is no use for somebody else's collection: it is not yours to set,
-- and changing it would move the shelf for them too.
--
-- list_follows is already your row about their collection — one per
-- (user_id, list_id), RLS'd so only you can see or change it. Your name for
-- where it sits goes there, and the app prefers it over the owner's when
-- drawing your own shelves.
--
-- Nullable and unset by default, so every existing follow keeps appearing
-- under Friends' Collections until somebody deliberately files it.

alter table public.list_follows
  add column if not exists topic text;

comment on column public.list_follows.topic is
  'Your shelf for someone else''s collection. Independent of hitlist_lists.topic, which is the owner''s.';
