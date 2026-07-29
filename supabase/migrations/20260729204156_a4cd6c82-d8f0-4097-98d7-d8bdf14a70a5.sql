CREATE OR REPLACE FUNCTION public.get_shared_recommendation(rec_id uuid)
RETURNS TABLE (
  id uuid,
  rating int,
  note text,
  created_at timestamptz,
  photo_url text,
  photo_urls text[],
  item_id uuid,
  item_type text,
  item_title text,
  item_subtitle text,
  item_image_url text,
  item_genre text,
  author_username text,
  author_display_name text,
  author_avatar_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    r.id,
    r.rating,
    r.note,
    r.created_at,
    r.photo_url,
    r.photo_urls,
    i.id AS item_id,
    i.type::text AS item_type,
    i.title AS item_title,
    i.subtitle AS item_subtitle,
    i.image_url AS item_image_url,
    i.genre AS item_genre,
    p.username AS author_username,
    p.display_name AS author_display_name,
    p.avatar_url AS author_avatar_url
  FROM public.recommendations r
  JOIN public.items i ON i.id = r.item_id
  LEFT JOIN public.profiles p ON p.id = r.user_id
  WHERE r.id = rec_id
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_shared_recommendation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shared_recommendation(uuid) TO anon, authenticated;