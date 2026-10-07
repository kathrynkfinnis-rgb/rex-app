-- Oct 7 — "some of the places on the list are erroneous, can you make it so
-- that left swipe gives the delete option?"
--
-- Yes, but deleting an item is a bigger thing than it looks and the screen has
-- to say so. items.id is referenced ON DELETE CASCADE from recommendations and
-- wants, so removing one takes every Rex and every want of it with it — for
-- everybody, not just the person swiping. On a list of nearly two hundred rows
-- being worked through quickly, that is exactly the sort of action that wants
-- to tell you what it is about to do.
--
-- Hence two functions rather than one. The first reports; the second acts.
--
-- Both are admin-only, and the gate lives here rather than only in the app.
-- The app's own check is a courtesy to the person using it; this is the one
-- that matters, because a screen that hides a button is not access control.
-- There is also no DELETE grant on items for authenticated at all — by
-- design since July — so this is the only route, and it is a narrow one.

-- The list the screen shows, with enough to judge each row by.
CREATE OR REPLACE FUNCTION public.places_without_pin()
RETURNS TABLE (
  id uuid,
  type text,
  title text,
  subtitle text,
  address text,
  image_url text,
  rex_count bigint,
  want_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    i.id, i.type::text, i.title, i.subtitle, i.address, i.image_url,
    (SELECT count(*) FROM public.recommendations r WHERE r.item_id = i.id),
    (SELECT count(*) FROM public.wants w WHERE w.item_id = i.id)
  FROM public.items i
  WHERE public.has_role(auth.uid(), 'admin')
    AND i.type::text IN ('place', 'event')
    AND i.lat IS NULL
  ORDER BY i.title
  LIMIT 500;
$$;

-- Deliberately narrow: it will only delete something that is on that list.
-- An item with coordinates is a place somebody has actually located, and this
-- function is for clearing out the ones that were never real — a mis-parsed
-- import row, a heading that became a place. Anything else keeps the ordinary
-- route, where you delete your own Rex and the item goes when nothing is left.
CREATE OR REPLACE FUNCTION public.delete_place_without_pin(_item uuid)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  removed integer;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'not allowed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.items i
    WHERE i.id = _item
      AND i.type::text IN ('place', 'event')
      AND i.lat IS NULL
  ) THEN
    RAISE EXCEPTION 'that place is on the map, so this is not the way to remove it';
  END IF;

  SELECT
    (SELECT count(*) FROM public.recommendations r WHERE r.item_id = _item)
    + (SELECT count(*) FROM public.wants w WHERE w.item_id = _item)
  INTO removed;

  -- The cascade does the rest; saying so out loud because a DELETE on one
  -- table quietly emptying two others is the kind of thing that should be
  -- written down next to it.
  DELETE FROM public.items WHERE id = _item;

  RETURN removed;
END;
$$;

REVOKE ALL ON FUNCTION public.places_without_pin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.places_without_pin() TO authenticated;

REVOKE ALL ON FUNCTION public.delete_place_without_pin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_place_without_pin(uuid) TO authenticated;

COMMENT ON FUNCTION public.delete_place_without_pin(uuid) IS
  'Removes a place that has no coordinates, and everything referencing it, for an admin only. Returns how many Rex and wants went with it. Refuses anything already on the map.';
