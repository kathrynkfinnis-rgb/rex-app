-- #149: "Add to trip" (and the same would happen for lists) failed with a
-- duplicate-key error whenever the place being added was one you'd already
-- Rex'd on its own. The original constraint,
--   CONSTRAINT recommendations_unique UNIQUE (user_id, item_id)
-- treated "you've Rex'd this place" as one global fact per user, so adding
-- the same place as a stop on a trip (or an item in a list) collided with
-- your standalone take on it — even though those are conceptually
-- different rows (a trip stop has its own rating/note, separate from
-- whatever you said about the place generally).
--
-- Split into three partial unique indexes, one per "shape" a recommendation
-- can take, so each context gets its own slot:
--   - standalone (trip_id and list_id both null): at most one per place
--   - a stop on a given trip: at most one per (place, trip)
--   - an item in a given list: at most one per (place, list)
-- The same place can now be Rex'd standalone AND live on any number of
-- different trips/lists, while still blocking a genuine duplicate within
-- the same context (adding the same place twice to the same trip, etc.).
ALTER TABLE public.recommendations DROP CONSTRAINT IF EXISTS recommendations_unique;

CREATE UNIQUE INDEX IF NOT EXISTS recommendations_unique_standalone
  ON public.recommendations (user_id, item_id)
  WHERE trip_id IS NULL AND list_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS recommendations_unique_trip_stop
  ON public.recommendations (user_id, item_id, trip_id)
  WHERE trip_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS recommendations_unique_list_item
  ON public.recommendations (user_id, item_id, list_id)
  WHERE list_id IS NOT NULL;
