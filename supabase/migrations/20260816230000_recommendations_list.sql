-- "List" as a type of Rex, structurally identical to how Trip already works:
-- the list itself is one recommendation (items.type = 'list'), and each
-- item on it is its own real recommendation linked back via list_id -
-- exactly the trip_id/trip_section pattern, so it can reuse the same
-- create/fetch code paths rather than inventing a parallel concept.
--
-- The one real difference from Trip: a trip's stops are unconditionally
-- hidden from the main feed (trip_id IS NULL is the feed's whole filter).
-- A list's items default to visible instead, with a per-item toggle -
-- "some Rex would not be on the feed" was explicit in the ask, so this
-- needs to be a column or the feed can't tell which items to include.
ALTER TABLE public.recommendations ADD COLUMN IF NOT EXISTS list_id uuid REFERENCES public.recommendations(id) ON DELETE CASCADE;
ALTER TABLE public.recommendations ADD COLUMN IF NOT EXISTS list_section text;
ALTER TABLE public.recommendations ADD COLUMN IF NOT EXISTS show_in_feed boolean NOT NULL DEFAULT true;
CREATE INDEX IF NOT EXISTS recommendations_list_id_idx ON public.recommendations(list_id);

-- No new RLS policy needed - list items are ordinary recommendations rows,
-- already covered by "See own and friends' recommendations".
