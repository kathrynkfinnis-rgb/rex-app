-- Oct 16, security review — findings F3, F4, F15, and two more the live
-- schema turned up that the migration files didn't show.
--
-- One mistake, eleven times. A policy asks "is this row mine?" and forgets
-- "am I allowed to see the thing it hangs off?". Ownership is not visibility,
-- and on a database the app taltablename,policyname
recommendation_tags,Tags are visible with the Rex
want_tags,Want tags are visible with the wantks to directly, the policy is the only place
-- that distinction can be made.
--
-- Written against `pg_policies` on the live database rather than against this
-- folder. Twice today the two disagreed — `profiles.interests` has never
-- existed in production, and `profiles` was carrying a second, more
-- permissive SELECT policy that no migration here creates. Every predicate
-- below was read back from the running schema before being replaced.
--
-- The pattern used throughout is `exists (select 1 from <parent> where id =
-- <fk>)`. A policy that references another table has that table's own RLS
-- applied as the calling user, so this reads as "if you can see the parent"
-- without restating the friendship rules — and it cannot drift out of step
-- with them later.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Likes and comments on a Rex (F4)
--
-- The insert check was ownership alone, so any signed-in user could attach
-- text to any recommendation id — and recommendation ids are not secret:
-- the share pages hand them out, and until this migration the tag tables
-- listed them wholesale (part 4 below).
--
-- The notification triggers then faithfully deliver that text to the owner's
-- phone. `request_comments`, written two days after these, got it right —
-- which is what makes this an oversight rather than a decision. Its shape is
-- what the two below now use.
-- ─────────────────────────────────────────────────────────────────────
drop policy if exists "Users insert own likes" on public.recommendation_likes;
create policy "Users insert own likes" on public.recommendation_likes
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (select 1 from public.recommendations r where r.id = recommendation_id)
  );

drop policy if exists "Users insert own comments" on public.recommendation_comments;
create policy "Users insert own comments" on public.recommendation_comments
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (select 1 from public.recommendations r where r.id = recommendation_id)
  );

-- ─────────────────────────────────────────────────────────────────────
-- 2. Moving a comment after the fact
--
-- Not in the original findings — the live dump is what showed it. Both
-- update policies had a USING and no WITH CHECK, and Postgres silently
-- reuses USING for the new row. USING pinned `user_id` and nothing else, so
-- the parent id was free: write a comment on your own Rex, then repoint it
-- at a stranger's.
--
-- This is the same shape as the friendship hole fixed this morning — a write
-- check that constrains who you are but not what you may touch.
--
-- A policy cannot compare the new row against the old one, so this does not
-- freeze the parent id. It does something better suited to the actual risk:
-- wherever you move the comment, it has to be somewhere you can see.
-- ─────────────────────────────────────────────────────────────────────
drop policy if exists "Users update own comments" on public.recommendation_comments;
create policy "Users update own comments" on public.recommendation_comments
  for update to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (select 1 from public.recommendations r where r.id = recommendation_id)
  );

drop policy if exists "Users update own request comments" on public.request_comments;
create policy "Users update own request comments" on public.request_comments
  for update to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (select 1 from public.requests q where q.id = request_id)
  );

-- ─────────────────────────────────────────────────────────────────────
-- 3. Likes and comments on a want (F4)
--
-- Written as FOR ALL, so USING governs select/update/delete and WITH CHECK
-- governs insert/update. Only the write half needs the parent test; the read
-- half is left as ownership, because a separate SELECT policy ("readable
-- with the want") already handles reading and permissive policies OR.
-- ─────────────────────────────────────────────────────────────────────
drop policy if exists "want_likes are your own to write" on public.want_likes;
create policy "want_likes are your own to write" on public.want_likes
  for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.wants w where w.id = want_id)
  );

drop policy if exists "want_comments are your own to write" on public.want_comments;
create policy "want_comments are your own to write" on public.want_comments
  for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.wants w where w.id = want_id)
  );

-- ─────────────────────────────────────────────────────────────────────
-- 4. Writing into somebody else's collection (F15)
--
-- The update policies on both tables already carry the right clause — added
-- 31 July — and the insert policies never got it. So the rule was "you may
-- not move a row into a collection you can't edit, but you may put one there
-- to begin with", which is not a rule.
--
-- `can_view_list` admits any public collection, and public collection ids are
-- handed to every signed-in user. The collection page reads by list_id alone,
-- so an injected row renders inside someone else's published collection — and
-- for a public one, `get_shared_collection_items` serves it to the open
-- internet.
--
-- The clause below is copied verbatim from the update policies rather than
-- rewritten, so the two halves cannot disagree.
--
-- saved_posts additionally gets the parent test from part 1: a save points at
-- a recommendation, and saving one you cannot see has the same shape as
-- commenting on it.
-- ─────────────────────────────────────────────────────────────────────
drop policy if exists "Users insert own saves" on public.saved_posts;
create policy "Users insert own saves" on public.saved_posts
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (select 1 from public.recommendations r where r.id = recommendation_id)
    and (
      list_id is null
      or can_edit_list(list_id, auth.uid())
      or can_view_list(list_id, auth.uid())
    )
  );

drop policy if exists "Users insert own wants" on public.wants;
create policy "Users insert own wants" on public.wants
  for insert to authenticated with check (
    auth.uid() = user_id
    and (
      list_id is null
      or can_edit_list(list_id, auth.uid())
      or can_view_list(list_id, auth.uid())
    )
  );

-- ─────────────────────────────────────────────────────────────────────
-- 5. Tag visibility (F3)
--
-- `USING (true)` returned every row of both tables to every signed-in user.
-- The stated reasoning — "a tag is shown on the card, it is not a secret" —
-- is right about a card you can already see, and the policy was not scoped
-- to that.
--
-- The real cost was not the tag graph but the ids. The share functions are
-- capability URLs: holding the id *is* the permission. These tables were
-- publishing the ids, wholesale, which turned "anyone with the link" into
-- "anyone with an account".
--
-- Scoped to the parent, with one addition: you can always see a tag that
-- names you, even on something you cannot otherwise see. Otherwise being
-- tagged in a stranger's Rex would notify you about a thing you then could
-- not find, and "Rex you were tagged in" would quietly lose rows.
-- ─────────────────────────────────────────────────────────────────────
drop policy if exists "Tags are visible to anyone" on public.recommendation_tags;
create policy "Tags are visible with the Rex" on public.recommendation_tags
  for select to authenticated using (
    user_id = auth.uid()
    or exists (select 1 from public.recommendations r where r.id = recommendation_id)
  );

drop policy if exists "Want tags are visible to anyone" on public.want_tags;
create policy "Want tags are visible with the want" on public.want_tags
  for select to authenticated using (
    user_id = auth.uid()
    or exists (select 1 from public.wants w where w.id = want_id)
  );

comment on table public.recommendation_tags is
  'Friends tagged on a Rex. Readable with the Rex itself, or by the person named — not by everyone, which is what turned this table into a list of recommendation ids for the share-link functions.';
