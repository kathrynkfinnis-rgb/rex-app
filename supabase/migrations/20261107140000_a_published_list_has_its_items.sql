-- Nov 8, after the fact: THIS WAS NOT PHOEBE'S BUG, and this migration
-- updated nothing when it was run. Keeping it, because the hole it closes is
-- real and the record of being wrong is worth more than a tidy file.
--
-- Her list's twenty items all had a published_at, set at the same moment as
-- the list itself in August. What actually happened is in NotificationsView:
-- a notification about a list routed by item id into ItemDetailView, which
-- draws a title, a cover, "Rex'd by" and "What friends say" and knows nothing
-- about contents. The screenshot was never the list page. It was the generic
-- item page, which is why there was not even an empty state on it — and
-- "Nothing on this list yet." would have told us that in one glance.
--
-- The lesson is the cheap check I skipped: "What friends say" appears in
-- exactly one file, and it is not ListDetailView. Grepping the words in the
-- screenshot would have found that before any of the SQL below was written.
--
-- What is below still stands on its own. The publish path genuinely did not
-- know about list_id, so a list drafted and then published would have left
-- every item unpublished. It had not bitten yet because a list built in one
-- sitting is created already published. The original note follows.
--
-- ─────────────────────────────────────────────────────────────────────
--
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
