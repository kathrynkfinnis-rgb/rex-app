-- Oct 7 — "you can't edit posts by REX."
--
-- Admins have been able to post as the official account since 5 October, and
-- then couldn't touch what they had posted. The policy from July is
-- "auth.uid() = user_id", and a Rex posted as REX belongs to the official
-- account rather than to the person who wrote it — so the one kind of post
-- that is nobody's personal opinion was the one kind nobody could correct.
--
-- Deliberately narrow, and worth being explicit about why. This is not "admins
-- can edit anything": an admin editing what a friend wrote about a restaurant
-- would be putting words in their mouth, and no amount of being on the team
-- makes that all right. It is only the official account, which is the team's
-- own voice and has no personal opinion to misrepresent.
--
-- Both policies are additive — Postgres ORs permissive policies together — so
-- the existing "own recommendations" rules are untouched and everybody keeps
-- exactly what they had.

drop policy if exists "Admins manage REX's recommendations update" on public.recommendations;
create policy "Admins manage REX's recommendations update"
  on public.recommendations for update to authenticated
  using (
    user_id = public.official_account_id()
    and public.has_role(auth.uid(), 'admin')
  );

-- Delete as well: a post made in the team's voice that turns out to be wrong
-- should be removable by the team, and leaving it editable but undeletable
-- would be a strange half-measure.
drop policy if exists "Admins manage REX's recommendations delete" on public.recommendations;
create policy "Admins manage REX's recommendations delete"
  on public.recommendations for delete to authenticated
  using (
    user_id = public.official_account_id()
    and public.has_role(auth.uid(), 'admin')
  );

comment on policy "Admins manage REX's recommendations update" on public.recommendations is
  'An admin may edit what was posted as REX, and nothing else. Being on the team is not a licence to edit what other people wrote.';
