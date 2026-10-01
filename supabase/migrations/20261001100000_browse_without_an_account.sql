-- Oct 1 — App Store review, Guideline 5.1.1(v): "the app requires users to
-- register or log in to access features that are not account based."
--
-- They're right, and only about one thing. The feed, map, collections and
-- Talk to Rex all show recommendations made by people you are friends with —
-- none of that can exist without an account, and none of it is opening up.
--
-- But Explore's "Rex from Rexperts" tab is REX's own curated shelves plus
-- what's most Rex'd across the app this week. That is editorial content. It
-- doesn't depend on who you are, and it has been sitting behind a sign-up
-- wall. This migration lets a signed-out visitor read exactly that and
-- nothing else.
--
-- What stays shut: every table holding somebody's own Rex, note, rating,
-- photo, friendship, want, collection, comment or profile. anon gains no new
-- access to any of them.

-- ============================================================ curated shelves
-- The shelves are written by three named curators and meant to be read by
-- everyone; "everyone" simply never included people who hadn't signed up yet.
drop policy if exists "Editorial collections are readable by anyone" on public.editorial_collections;
create policy "Editorial collections are readable by anyone"
  on public.editorial_collections for select to anon using (true);

drop policy if exists "Editorial collection items are readable by anyone" on public.editorial_collection_items;
create policy "Editorial collection items are readable by anyone"
  on public.editorial_collection_items for select to anon using (true);

grant select on public.editorial_collections to anon;
grant select on public.editorial_collection_items to anon;

-- ============================================================ trending
-- Counts across the whole app for the last seven days. Worth being explicit
-- about what this returns before handing it to the public internet: an item's
-- id, title, subtitle, image and type, and how many people Rex'd it. No user
-- id, no username, no note, no rating, no ownership — you cannot learn from
-- this who recommended anything, only that a place is popular.
--
-- It already excludes trip stops and unpublished drafts, and that matters
-- more now: SECURITY DEFINER means it runs with the owner's rights, so those
-- two filters are the only thing standing between a draft and a stranger.
grant execute on function public.trending_items_weekly(integer) to anon;

comment on function public.trending_items_weekly(integer) is
  'Most-Rex''d items of the last 7 days. Readable signed-out (App Store 5.1.1(v)); returns item facts and a count only, never who recommended them.';
