-- Oct 16, security review — Critical.
--
-- Any user could make themselves your friend, and you were never told.
--
-- The policy was named for what it was meant to do and written to do more:
--
--   CREATE POLICY "Recipient can update friendship (accept)"
--     ON public.friendships FOR UPDATE TO authenticated
--     USING (auth.uid() = addressee_id OR auth.uid() = requester_id);
--
-- Two faults, and either alone would have been enough. The predicate admits
-- the requester as well as the recipient. And with no WITH CHECK, Postgres
-- applies USING to the *new* row too — so the row that results from the
-- update is tested by the same permissive clause.
--
-- So: send a request, then PATCH your own row to status 'accepted'.
-- are_friends() tests only the pair and the status, never who set it, and it
-- is the authorisation primitive for nearly everything — recommendations,
-- wants, blasts, rankings, ticket reminders, and the storage buckets holding
-- people's photographs.
--
-- Silent, too: tg_notify_friend_accepted notifies NEW.requester_id, which is
-- the attacker. The person whose content just became readable hears nothing.
--
-- Checked before writing this: the policy is created exactly once across all
-- migrations and never redefined, and the only BEFORE UPDATE trigger on the
-- table is friendships_touch, which stamps updated_at and guards nothing.
--
-- Accepting is the recipient's act alone. A requester who wants out already
-- has the DELETE policy, which is the honest shape for cancelling — it
-- removes the request rather than transitioning it.
--
-- Checked that this breaks nothing: respondToFriendRequest is the only client
-- write that PATCHes a friendship, and all three of its callers only offer
-- Accept to the addressee. UserProfileView shows the button solely in the
-- "requested_you" state (the requester gets "Request sent", no action), and
-- FriendsView and NotificationsView both act on an incoming request. So no
-- legitimate path was relying on the requester half of the old predicate.
drop policy if exists "Recipient can update friendship (accept)" on public.friendships;

create policy "Recipient can update friendship (accept)"
  on public.friendships for update to authenticated
  using (auth.uid() = addressee_id)
  with check (auth.uid() = addressee_id);

comment on table public.friendships is
  'Only the addressee may update a row (i.e. accept). The requester cancels by deleting. Both halves of the UPDATE policy are stated explicitly: without WITH CHECK, Postgres reuses USING for the new row, which is how the 26 July policy let a requester accept their own request.';
