-- Sept 5 — "ensure that the top rex in the list in the import comes at the
-- top of the list (currently order is inverted)".
--
-- insertStagingRows POSTs every extracted row in a single request, so they
-- all land in one transaction and share an identical created_at (now() is
-- fixed for the life of a transaction in Postgres). Ordering the review
-- screen by created_at was therefore ordering by nothing at all — the rows
-- came back in whatever order the planner felt like, which in practice
-- read as reversed.
--
-- An explicit ordinal is the only thing that actually preserves the order
-- the document was written in.
alter table public.import_staging
  add column if not exists sort_order integer;

-- Existing pending rows have no meaningful order to recover, so they keep
-- NULL; the review screen sorts NULLs last and falls back to created_at,
-- which is no worse than what they have today.
create index if not exists import_staging_source_sort_idx
  on public.import_staging (source, sort_order);
