-- Oct 5 — "I just tried to share a collection, and it's just the list of
-- places truncated", and "every time anything gets shared on WhatsApp, it
-- should have the link."
--
-- A Rex and a trip have had public pages since July (/r/<id> and /t/<id>, via
-- get_shared_recommendation and get_shared_trip). A collection never did, so
-- the app did the only thing it could and pasted the first twelve titles into
-- the message with "...and 9 more". Nothing to open, nothing to preview, and
-- nothing for a stranger to join from — which matters more now that a share is
-- meant to be the way in.
--
-- Same shape as the trip pair deliberately: one function for the collection
-- itself, one for its contents, both SECURITY DEFINER so a logged-out visitor
-- can read them, and both refusing anything the owner hasn't published.
--
-- That last part is the whole safety argument. These bypass RLS, so the
-- WHERE clause is the access control: only a collection explicitly set to
-- 'public' is ever returned. A draft or friends-only collection is not found,
-- the same as one that doesn't exist — a share link for it simply 404s rather
-- than leaking what somebody has been saving privately.
CREATE OR REPLACE FUNCTION public.get_shared_collection(_list uuid)
RETURNS TABLE(
  id uuid, name text, emoji text, item_type text, created_at timestamptz,
  owner_username text, owner_display_name text, owner_avatar_url text,
  item_count bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT l.id, l.name, l.emoji, l.item_type, l.created_at,
         p.username, p.display_name, p.avatar_url,
         (SELECT count(*) FROM public.saved_posts sp WHERE sp.list_id = l.id)
  FROM public.hitlist_lists l
  LEFT JOIN public.profiles p ON p.id = l.user_id
  WHERE l.id = _list
    AND l.visibility = 'public'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_shared_collection_items(_list uuid)
RETURNS TABLE(
  recommendation_id uuid, rating integer, note text,
  item_id uuid, item_type text, item_title text, item_subtitle text,
  item_image_url text, item_genre text, item_address text,
  author_username text, author_display_name text,
  section text, sort_order integer
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT r.id, r.rating, r.note,
         i.id, i.type, i.title, i.subtitle, i.image_url, i.genre, i.address,
         p.username, p.display_name,
         sp.section, sp.sort_order
  FROM public.saved_posts sp
  JOIN public.hitlist_lists l ON l.id = sp.list_id AND l.visibility = 'public'
  JOIN public.recommendations r ON r.id = sp.recommendation_id
  JOIN public.items i ON i.id = r.item_id
  LEFT JOIN public.profiles p ON p.id = r.user_id
  WHERE sp.list_id = _list
  ORDER BY sp.sort_order NULLS LAST, sp.created_at;
$$;

REVOKE ALL ON FUNCTION public.get_shared_collection(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_shared_collection_items(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shared_collection(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_shared_collection_items(uuid) TO anon, authenticated;
