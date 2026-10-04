-- Oct 4 — "Rexes for the same place didn't combine."
--
-- Two Grand Central Oyster Bar rows in the catalogue:
--   053f6474-3083-4c73-80e4-eb26efa6df62  no address, no coordinates (typed)
--   3fd5d6ca-cf84-4a7d-809d-5ba9b844adca  89 E 42nd St (picked from Google)
--
-- createItem's two dedupe checks each need something the other row also has —
-- the same Google place id, or coordinates on both — and a hand-typed place
-- has neither. A third check now matches on name plus address, which stops the
-- common case, but it can't help here: the typed row has no address at all.
--
-- So this is a one-off repair of the pair, not a rule. Everything pointing at
-- the typed row is repointed at the Google-backed one, which is the row worth
-- keeping: it has the address and the coordinates, so it is the one that can
-- draw a pin.
--
-- Written to survive the unique indexes. Repointing a recommendation onto an
-- item the same person has already Rex'd would violate
-- recommendations_unique_standalone, so those are dropped rather than moved:
-- it is the same person saying the same thing about the same place twice.
DO $$
DECLARE
  loser  uuid := '053f6474-3083-4c73-80e4-eb26efa6df62';
  keeper uuid := '3fd5d6ca-cf84-4a7d-809d-5ba9b844adca';
BEGIN
  -- Drop the ones that would collide, per context, then move the rest.
  DELETE FROM public.recommendations r
  WHERE r.item_id = loser
    AND EXISTS (
      SELECT 1 FROM public.recommendations k
      WHERE k.item_id = keeper
        AND k.user_id = r.user_id
        AND k.trip_id IS NOT DISTINCT FROM r.trip_id
        AND k.list_id IS NOT DISTINCT FROM r.list_id
    );
  UPDATE public.recommendations SET item_id = keeper WHERE item_id = loser;

  DELETE FROM public.wants w
  WHERE w.item_id = loser
    AND EXISTS (SELECT 1 FROM public.wants k WHERE k.item_id = keeper AND k.user_id = w.user_id);
  UPDATE public.wants SET item_id = keeper WHERE item_id = loser;

  DELETE FROM public.rex_suggestions s
  WHERE s.item_id = loser
    AND EXISTS (SELECT 1 FROM public.rex_suggestions k WHERE k.item_id = keeper AND k.user_id = s.user_id);
  UPDATE public.rex_suggestions SET item_id = keeper WHERE item_id = loser;

  UPDATE public.editorial_collection_items SET item_id = keeper WHERE item_id = loser;
  UPDATE public.check_ins SET item_id = keeper WHERE item_id = loser;
  UPDATE public.request_comments SET suggested_item_id = keeper WHERE suggested_item_id = loser;
  UPDATE public.import_staging SET resolved_item_id = keeper WHERE resolved_item_id = loser;

  DELETE FROM public.items WHERE id = loser;
END $$;
