ALTER TABLE public.hitlist_lists ADD COLUMN IF NOT EXISTS view_count integer NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.increment_list_view(_list uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.hitlist_lists
     SET view_count = view_count + 1
   WHERE id = _list AND visibility = 'public';
END;
$$;

REVOKE ALL ON FUNCTION public.increment_list_view(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_list_view(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.public_collections(_limit integer DEFAULT 50)
RETURNS TABLE(id uuid, name text, emoji text, view_count integer, created_at timestamptz, owner_id uuid, owner_username text, owner_display_name text, owner_avatar_url text, item_count bigint)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT l.id, l.name, l.emoji, l.view_count, l.created_at,
         p.id, p.username, p.display_name, p.avatar_url,
         (SELECT count(*) FROM public.wants w WHERE w.list_id = l.id)
         + (SELECT count(*) FROM public.saved_posts s WHERE s.list_id = l.id)
  FROM public.hitlist_lists l
  LEFT JOIN public.profiles p ON p.id = l.user_id
  WHERE l.visibility = 'public'
  ORDER BY l.view_count DESC, l.created_at DESC
  LIMIT LEAST(GREATEST(coalesce(_limit, 50), 1), 200);
$$;

REVOKE ALL ON FUNCTION public.public_collections(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.public_collections(integer) TO authenticated;