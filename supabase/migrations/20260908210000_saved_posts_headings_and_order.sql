-- Sept 8 — "have the same import style that we have just built for trips
-- and lists with headings and drag and drop".
--
-- A collection couldn't do either half. saved_posts is a plain join table
-- (user, recommendation, list) with no heading and no position, so
-- fetchCollectionItems falls back to created_at desc — the order things
-- happened to be added in, newest first. That's why a document imported
-- into a collection has to be inserted backwards to read the right way up,
-- and why there was nowhere to put "Pubs" and "Galleries" as headings.
--
-- Two columns, deliberately the same shape trips and lists already use:
-- a heading is a repeated string on each row (trip_section/list_section),
-- not a table of its own, and position is an explicit integer because
-- created_at can't carry it (a batch insert shares now(), which is what
-- broke trip import order on 5 Sept).

alter table public.saved_posts
  add column if not exists section text,
  add column if not exists sort_order integer;

-- Existing collections keep the order they currently display in. They read
-- created_at desc today, so the newest row becomes position 0 and the
-- sequence runs backwards through time from there — the list looks
-- untouched the moment the app switches to ordering by this column.
update public.saved_posts as s
set sort_order = numbered.position
from (
  select id,
         (row_number() over (partition by list_id order by created_at desc)) - 1 as position
  from public.saved_posts
) as numbered
where s.id = numbered.id
  and s.sort_order is null;

-- Ordering is per collection, so the index leads with list_id. Nulls last
-- keeps a row added by an older client (or by any code path that hasn't
-- been taught to set a position yet) at the end rather than at the top.
create index if not exists saved_posts_list_order_idx
  on public.saved_posts (list_id, sort_order nulls last, created_at desc);
