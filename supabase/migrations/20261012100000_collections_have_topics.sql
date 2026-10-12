-- Oct 12 — "being able to order and title your collections into topic."
--
-- My Collections is one shelf of up to eight tiles with a "see all" at the
-- end. That was right when there were four; it stops working at twenty,
-- because a flat shelf of twenty things has no shape and the only way to find
-- one is to remember roughly where you left it.
--
-- Two columns, and they do different jobs.
--
-- `topic` is the heading a collection sits under — "London", "Baby", "Books
-- to read". Free text rather than a table of its own: a topic has no
-- properties beyond its name, nothing else refers to it, and making it a
-- table would mean a second thing to create and tidy up before you could use
-- the first. Renaming one is an UPDATE across the collections that carry it,
-- which is what people expect renaming a folder to do.
--
-- `sort_order` is the order you put them in. Null means "not placed", and
-- those sort after anything that has been — so a new collection appears at
-- the end rather than silently in the middle of a list somebody arranged.
alter table public.hitlist_lists
  add column if not exists topic text,
  add column if not exists sort_order integer;

comment on column public.hitlist_lists.topic is
  'The heading this collection sits under on the Collections tab. Free text, owner''s own words, null for ungrouped. Renaming a topic updates every collection carrying it.';

comment on column public.hitlist_lists.sort_order is
  'Where it sits among its siblings. Null sorts last, so a new collection lands at the end rather than in the middle of an order somebody arranged.';

-- Grouped and ordered reads happen on every visit to the tab.
create index if not exists hitlist_lists_user_topic_idx
  on public.hitlist_lists (user_id, topic, sort_order);
