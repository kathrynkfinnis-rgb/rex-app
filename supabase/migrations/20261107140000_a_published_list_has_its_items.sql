-- Nov 7, from Phoebe: "I tagged Alex in the list and then only this came up,
-- i.e. not the actual list." A list page with its title, its cover and her
-- comment on it, and not one item.
--
-- The code fix is in RexAPI.swift. publishTrip, which publishDraft calls,
-- matched `id.eq.X or trip_id.eq.X` and nothing else, on the strength of a
-- comment claiming a list's items hang off trip_id the way a trip's stops do.
-- They do not — fetchListItems filters on list_id — so publishing a draft
-- list published the list row and left every item in it unpublished. An
-- unpublished row is visible to its author and to no one else, which is
-- exactly what Phoebe and Alex each saw.
--
-- That fixes it from now on. This fixes the lists it already happened to,
-- which is the half a code change cannot reach.
--
-- The rule: an item whose list has been published should be published too,
-- with its parent's timestamp rather than now(), so a list shared in
-- September does not resurface at the top of everybody's feed tonight.
--
-- There is no way in either app to draft a single item inside a published
-- list — drafting is a whole-list action — so every row this matches is a
-- casualty of the bug rather than somebody's deliberate choice.
update public.recommendations as child
set published_at = parent.published_at
from public.recommendations as parent
where child.list_id = parent.id
  and child.published_at is null
  and parent.published_at is not null;

-- The same shape for trips, which was never broken, as a belt-and-braces
-- check: if this updates anything it means a trip went out with queued stops
-- at some point, and publishQueuedPost had the same list_id blind spot until
-- today.
update public.recommendations as child
set published_at = parent.published_at
from public.recommendations as parent
where child.trip_id = parent.id
  and child.published_at is null
  and parent.published_at is not null;
