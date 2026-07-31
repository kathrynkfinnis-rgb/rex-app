DROP FUNCTION IF EXISTS public.get_shared_trip(uuid);
DROP FUNCTION IF EXISTS public.get_shared_trip_stops(uuid);

CREATE OR REPLACE FUNCTION public.get_shared_trip(_trip uuid)
RETURNS TABLE(
  id uuid, rating integer, note text, created_at timestamptz,
  photo_url text, photo_urls text[],
  item_id uuid, item_title text, item_subtitle text, item_image_url text,
  author_username text, author_display_name text, author_avatar_url text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT r.id, r.rating, r.note, r.created_at, r.photo_url, r.photo_urls,
         i.id, i.title, i.subtitle, i.image_url,
         p.username, p.display_name, p.avatar_url
  FROM public.recommendations r
  JOIN public.items i ON i.id = r.item_id
  LEFT JOIN public.profiles p ON p.id = r.user_id
  WHERE r.id = _trip AND i.type = 'trip'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_shared_trip_stops(_trip uuid)
RETURNS TABLE(
  id uuid, rating integer, note text, created_at timestamptz,
  photo_url text, photo_urls text[],
  item_id uuid, item_type text, item_title text, item_subtitle text,
  item_image_url text, item_genre text, item_address text,
  item_lat double precision, item_lng double precision,
  author_username text, author_display_name text, author_avatar_url text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT r.id, r.rating, r.note, r.created_at, r.photo_url, r.photo_urls,
         i.id, i.type::text, i.title, i.subtitle, i.image_url, i.genre, i.address, i.lat, i.lng,
         p.username, p.display_name, p.avatar_url
  FROM public.recommendations r
  JOIN public.items i ON i.id = r.item_id
  LEFT JOIN public.profiles p ON p.id = r.user_id
  WHERE r.trip_id = _trip
  ORDER BY r.created_at ASC;
$$;

REVOKE ALL ON FUNCTION public.get_shared_trip(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_shared_trip_stops(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shared_trip(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_shared_trip_stops(uuid) TO anon, authenticated, service_role;