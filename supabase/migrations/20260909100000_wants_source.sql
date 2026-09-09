-- Sept 9 — "when Gemma saves one of my Rex so it becomes a want to try for
-- her it shouldn't come up on the feed again."
--
-- Every want is one row in `wants`, however it got there, so the feed
-- can't tell the two kinds apart:
--
--   * you tapped the bookmark on somebody's Rex — a private save. The
--     thing was already in the feed once, as their Rex; showing it again
--     as your want is the same recommendation twice, and the second time
--     with your name on it.
--   * you added a want to try from scratch — you're telling people about
--     something nobody has Rex'd yet, which is real news and belongs in
--     the feed.
--
-- One column to say which. Deliberately not a boolean: "saved from
-- someone's Rex" and "added on its own" are the two we know about today,
-- and an import or a share would want its own name rather than to be
-- squeezed into true/false.

alter table public.wants
  add column if not exists source text;

-- Existing rows get the best guess available: if anyone has Rex'd the same
-- item, the want was almost certainly a save off the back of that Rex.
-- Wrong occasionally — two people can independently want the same
-- restaurant — but the cost of guessing wrong here is one card missing
-- from a feed, against the clutter of leaving every historic save in it.
update public.wants as w
set source = case
  when exists (
    select 1 from public.recommendations r
    where r.item_id = w.item_id and r.user_id <> w.user_id
  ) then 'save'
  else 'add'
end
where source is null;

create index if not exists wants_source_idx on public.wants (source, created_at desc);
