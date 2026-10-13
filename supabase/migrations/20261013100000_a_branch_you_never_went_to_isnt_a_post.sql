-- Oct 13 — "the 'others in the chain' shouldn't appear on the feed when you
-- Rex them."
--
-- Rexing the other Salad Kitchens is one act, not five. You went to the Leather
-- Lane one and said the brand is good; the other four rows exist so the pins
-- are on the map and so the branch pages carry your rating. They were never
-- meant to be four more things you told everybody.
--
-- The feed showed them because nothing distinguished them from a Rex you sat
-- down and wrote. The burst collapser didn't catch them either: it needs more
-- than five in a minute from one person, and a chain of four is under the bar —
-- and even at six, "+4 more" would still be the wrong answer rather than a
-- tidier wrong answer.
--
-- A column rather than a note convention, because the note is the user's text
-- and inferring intent from its wording would break the moment anybody edits
-- it. Null-free and defaulted, so every row already in the table is what it has
-- always been: a real post.
alter table public.recommendations
  add column if not exists is_branch_copy boolean not null default false;

comment on column public.recommendations.is_branch_copy is
  'True when this row was created by "Rex the other branches too" rather than written directly. It carries your rating onto the branch''s own page and pin, and stays out of the feed, because one visit is one recommendation however many addresses the brand has.';

-- The feed asks for everything-but-these on every load, so it is worth an
-- index that only holds the rows the feed actually wants.
create index if not exists recommendations_feed_not_branch_idx
  on public.recommendations (created_at desc) where not is_branch_copy;
