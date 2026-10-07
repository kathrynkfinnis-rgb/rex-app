-- Oct 7 — "lists are still coming up with ratings despite never having put
-- them in and not being able to edit them."
--
-- Both halves were true. approveStagingAsList and approveStagingAsTrip created
-- their container with a hard-coded rating of 8, which renders as 👌 on the
-- card, and nothing in the app offered a way to change it. Every other path
-- that makes a trip — BuildTripFromRex, AddToTrip, addStopToTrip — already
-- passed 0, the unrated sentinel this column has allowed since 15 August, so
-- the importer was the odd one out rather than the rule.
--
-- The two kinds are treated differently on purpose.
--
-- A list has every rating cleared. A list is a container for other people's
-- recommendations — "Best Butchers in London" is not a thing you rate out of
-- ten, and the stars belong to the butchers inside it. There is no rating
-- here worth preserving because there was never a way to set one deliberately.
--
-- A trip is a thing you actually went on, so one could legitimately be rated.
-- Those are only cleared where the rating is still exactly the importer's 8
-- AND the row has never been updated — recommendations_touch moves updated_at
-- on every UPDATE, so untouched means nobody has been near it since the
-- import. A trip someone did go back and rate keeps its rating. The trade is
-- deliberate: a spurious 8 may survive on a trip that was edited for some
-- other reason, which is a smaller wrong than deleting a rating somebody meant.
update public.recommendations r
set rating = 0
from public.items i
where i.id = r.item_id
  and i.type::text = 'list'
  and coalesce(r.rating, 0) <> 0;

update public.recommendations r
set rating = 0
from public.items i
where i.id = r.item_id
  and i.type::text = 'trip'
  and r.rating = 8
  and r.updated_at = r.created_at;
