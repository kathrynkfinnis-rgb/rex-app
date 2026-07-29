
CREATE OR REPLACE FUNCTION public.admin_kpis_engagement()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT jsonb_build_object(
    'total_users', (SELECT count(*) FROM auth.users),
    'activated_users', (SELECT count(DISTINCT user_id) FROM public.recommendations),
    'users_with_friend', (
      SELECT count(DISTINCT uid) FROM (
        SELECT requester_id AS uid FROM public.friendships WHERE status = 'accepted'
        UNION SELECT addressee_id FROM public.friendships WHERE status = 'accepted'
      ) t
    ),
    'friendships_accepted', (SELECT count(*) FROM public.friendships WHERE status = 'accepted'),
    'friendships_pending', (SELECT count(*) FROM public.friendships WHERE status = 'pending'),
    'friend_accept_rate', (
      SELECT CASE WHEN count(*) = 0 THEN 0
        ELSE round(100.0 * count(*) FILTER (WHERE status = 'accepted') / count(*)) END
      FROM public.friendships
    ),
    'avg_friends', (
      SELECT CASE WHEN (SELECT count(*) FROM auth.users) = 0 THEN 0
        ELSE round((2.0 * count(*)) / (SELECT count(*) FROM auth.users), 1) END
      FROM public.friendships WHERE status = 'accepted'
    ),
    'recs_per_active_user', (
      SELECT CASE WHEN count(DISTINCT user_id) = 0 THEN 0
        ELSE round(count(*)::numeric / count(DISTINCT user_id), 1) END
      FROM public.recommendations
    ),
    'recs_with_photo', (SELECT count(*) FROM public.recommendations WHERE coalesce(array_length(photo_urls, 1), 0) > 0 OR photo_url IS NOT NULL),
    'recs_with_note', (SELECT count(*) FROM public.recommendations WHERE note IS NOT NULL AND length(btrim(note)) > 0),
    'avg_rating', (SELECT coalesce(round(avg(rating)::numeric, 1), 0) FROM public.recommendations),
    'lists_total', (SELECT count(*) FROM public.hitlist_lists),
    'lists_published', (SELECT count(*) FROM public.hitlist_lists WHERE visibility <> 'draft'),
    'wants_total', (SELECT count(*) FROM public.wants),
    'items_total', (SELECT count(*) FROM public.items),
    'places_geocoded', (SELECT count(*) FROM public.items WHERE type = 'place' AND lat IS NOT NULL),
    'places_total', (SELECT count(*) FROM public.items WHERE type = 'place'),
    'blasts_answered', (
      SELECT count(*) FROM public.requests r
      WHERE EXISTS (SELECT 1 FROM public.request_comments c WHERE c.request_id = r.id)
    ),
    'blasts_total', (SELECT count(*) FROM public.requests),
    'imports_total', (SELECT count(*) FROM public.import_staging),
    'by_category', (
      SELECT coalesce(jsonb_agg(x ORDER BY (x->>'count')::int DESC), '[]'::jsonb) FROM (
        SELECT jsonb_build_object('type', i.type::text, 'count', count(*)) AS x
        FROM public.recommendations r JOIN public.items i ON i.id = r.item_id
        GROUP BY i.type
      ) s
    ),
    'signups_by_week', (
      SELECT coalesce(jsonb_agg(jsonb_build_object('week', wk, 'count', n) ORDER BY wk), '[]'::jsonb) FROM (
        SELECT date_trunc('week', created_at)::date AS wk, count(*) AS n
        FROM auth.users WHERE created_at >= now() - interval '8 weeks'
        GROUP BY 1
      ) s
    ),
    'recs_by_week', (
      SELECT coalesce(jsonb_agg(jsonb_build_object('week', wk, 'count', n) ORDER BY wk), '[]'::jsonb) FROM (
        SELECT date_trunc('week', created_at)::date AS wk, count(*) AS n
        FROM public.recommendations WHERE created_at >= now() - interval '8 weeks'
        GROUP BY 1
      ) s
    ),
    'top_contributors', (
      SELECT coalesce(jsonb_agg(jsonb_build_object('username', username, 'display_name', display_name, 'count', n) ORDER BY n DESC), '[]'::jsonb) FROM (
        SELECT p.username, p.display_name, count(*) AS n
        FROM public.recommendations r JOIN public.profiles p ON p.id = r.user_id
        GROUP BY p.username, p.display_name
        ORDER BY n DESC LIMIT 5
      ) s
    )
  ) INTO result;
  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_kpis_engagement() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_kpis_engagement() TO authenticated;
