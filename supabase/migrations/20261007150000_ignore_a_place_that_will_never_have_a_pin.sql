-- Oct 7 — "some of the places on the list are erroneous, can you make it so
-- that left swipe gives the delete option?" … "well maybe instead of deleting,
-- you can just remove from this list?"
--
-- Yes, and that is the better answer. Deleting an item is a much bigger thing
-- than the screen implies: items.id is referenced ON DELETE CASCADE from
-- recommendations and wants, so removing one would take every Rex and every
-- want of it with it, for everybody. On a list of two hundred rows being
-- worked through quickly, a swipe that can destroy somebody else's Rex is the
-- wrong tool no matter how well it is confirmed.
--
-- So nothing is deleted. A row is marked as not needing a pin and drops off
-- the list, and everything about it is left exactly where it was. The place
-- keeps working everywhere else; it simply stops being a chore.
--
-- Reversible on purpose: setting the column back to null puts it back on the
-- list. A maintenance screen should not be able to make permanent decisions.
alter table public.items
  add column if not exists pin_not_needed_at timestamptz;

comment on column public.items.pin_not_needed_at is
  'Set when somebody decides this place will never have a pin — a mis-parsed import row, a heading that became a place. It drops off the admin list of places with no coordinates and is otherwise untouched. Null puts it back.';

-- The list the screen shows, minus anything already dealt with.
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
  -- The admin gate lives here rather than only in the app. A screen that
  -- hides a button is not access control.
  WHERE public.has_role(auth.uid(), 'admin')
    AND i.type::text IN ('place', 'event')
    AND i.lat IS NULL
    AND i.pin_not_needed_at IS NULL
  ORDER BY i.title
  LIMIT 500;
$$;

CREATE OR REPLACE FUNCTION public.ignore_place_without_pin(_item uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'not allowed';
  END IF;

  -- Only ever a place that has no coordinates. This is not a general-purpose
  -- flag on any item somebody fancies hiding.
  UPDATE public.items
     SET pin_not_needed_at = now()
   WHERE id = _item
     AND type::text IN ('place', 'event')
     AND lat IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.places_without_pin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.places_without_pin() TO authenticated;

REVOKE ALL ON FUNCTION public.ignore_place_without_pin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ignore_place_without_pin(uuid) TO authenticated;

-- Oct 7 — "some are items / brands rather than places."
--
-- Those shouldn't be ignored, they should be put right. An item filed as a
-- place is wrong everywhere, not just on this list: it carries a place's
-- badge and colour on its card, it answers the Places filter, and it will sit
-- in the pin-less list for ever because it was never going to have a pin.
-- Moving it to Other fixes all of that and takes it off the list as a
-- side-effect, which is the better shape than hiding it where it is.
--
-- Only to 'other', and only from a place with no coordinates. A free-form
-- "change this to anything" would be a different and much larger power, and
-- not one a swipe on a maintenance screen should carry.
CREATE OR REPLACE FUNCTION public.place_is_actually_a_thing(_item uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'not allowed';
  END IF;

  UPDATE public.items
     SET type = 'other',
         -- An address on something that was never a place is leftover noise
         -- from whatever filed it wrongly in the first place.
         address = NULL
   WHERE id = _item
     AND type::text IN ('place', 'event')
     AND lat IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.place_is_actually_a_thing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_is_actually_a_thing(uuid) TO authenticated;

COMMENT ON FUNCTION public.place_is_actually_a_thing(uuid) IS
  'Moves something filed as a place into Other — a brand, a product, anything that was never somewhere you go. Admin only, and only from a place that has no coordinates.';

COMMENT ON FUNCTION public.ignore_place_without_pin(uuid) IS
  'Takes a place off the admin list of things missing a pin, without deleting anything. Admin only, and only for a place that genuinely has no coordinates.';
