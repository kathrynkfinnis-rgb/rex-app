-- Sept 29 — "please can you put want-to-trys under sub headings".
--
-- Looking at what was actually there turned up two faults underneath that
-- request, and the heading was the smaller of them.
--
-- 1. A want in a collection was invisible. AddWantToListView (18 Sept) writes
--    wants.list_id perfectly well, and 19 rows already carry one — Gemma's
--    Cornwall places among them — but nothing has ever read them back. The
--    collection page is built entirely from saved_posts, so "add to
--    collection" on a want wrote a row and then showed you nothing. That is
--    the real answer to "they don't show up in collections".
--
-- 2. Collection headings never persisted. Of 234 saved_posts, zero have a
--    section: fetchCollectionItems selects the column and then decodes a
--    struct that doesn't contain it, so a heading could never survive a
--    reload even if one were set. Fixed in the client alongside this.
--
-- This migration is only the column the wants half needs. It mirrors
-- recommendations.list_section exactly, so a want and a Rex can share a
-- heading and be sorted together.

alter table public.wants
  add column if not exists list_section text;

comment on column public.wants.list_section is
  'Heading this want sits under inside its collection. Mirrors recommendations.list_section.';

-- A deliberate position within the collection, so a want can be dragged
-- among the Rex rather than always sorting by date. Same meaning and same
-- null-handling as saved_posts.sort_order.
alter table public.wants
  add column if not exists list_sort_order integer;

comment on column public.wants.list_sort_order is
  'Position within the collection. Null sorts last, matching saved_posts.';

-- The only new query shape: everything in one collection, in order.
create index if not exists wants_list_idx
  on public.wants (list_id, list_sort_order nulls last, created_at desc)
  where list_id is not null;

-- wants already has "Users update own wants" (31 July), which is what the
-- app needs to set these two columns, so there is no new policy here. Worth
-- saying out loud rather than leaving the reader to check.
