-- Oct 14 — "users should be able to show Lists as full titles if it's more of
-- a 'to do' list format rather than a list of Rexes."
--
-- "Plant spring-flowering bulbs (daffodils, crocuses, alliums, hyacinths) for
-- co…" is a garden job, not a title. The three-line cut on a card is right for
-- a list of Rexes — those titles are names, and uniform cards read faster down
-- a column — and wrong for a list of jobs, where the cut takes the instruction
-- with it.
--
-- Which of the two a list is is something only its author knows, so they say.
-- On the list rather than on the device because the people they share it with
-- are reading the same list, and a to-do list that reads as a to-do list for
-- its author and a truncated list of Rexes for everyone else is the same bug
-- again with extra steps.
--
-- Null, not false, for every list that existed before this: nobody has been
-- asked yet, and the app reads an unanswered question as the old behaviour.
alter table public.recommendations
  add column if not exists list_full_titles boolean;

comment on column public.recommendations.list_full_titles is
  'Lists only. True when this is a to-do list whose item titles are instructions and should wrap rather than being cut at three lines. Null means never asked.';

-- No policy changes: this is a column on a row you already own, and the
-- existing update policy on recommendations already scopes writes to the
-- author.
