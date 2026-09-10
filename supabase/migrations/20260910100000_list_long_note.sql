-- Sept 10 — "a free text 'Notes' box at the bottom of lists so if the app
-- can't work out what is in the list as it is misc, you have the
-- opportunity to post free text instead. Especially helpful if there is
-- lots of commentary."
--
-- Separate from `note`, which is the one-line "why are you Rex'ing it"
-- shown on the list's feed card. This is the long-form kind, shown on the
-- list's own page. Existing RLS on recommendations already lets an owner
-- update their own row, so no policy change.

alter table public.recommendations
  add column if not exists long_note text;
