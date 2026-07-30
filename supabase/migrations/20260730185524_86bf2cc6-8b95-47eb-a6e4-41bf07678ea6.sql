CREATE OR REPLACE FUNCTION public.top_rexxers_weekly(_limit integer DEFAULT 5)
RETURNS TABLE(user_id uuid, username text, display_name text, avatar_url text, rex_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.username, p.display_name, p.avatar_url, count(r.id) AS rex_count
  FROM public.recommendations r
  JOIN public.profiles p ON p.id = r.user_id
  WHERE r.created_at >= now() - interval '7 days'
  GROUP BY p.id, p.username, p.display_name, p.avatar_url
  ORDER BY rex_count DESC, p.username ASC
  LIMIT greatest(1, least(coalesce(_limit, 5), 20))
$$;

REVOKE ALL ON FUNCTION public.top_rexxers_weekly(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.top_rexxers_weekly(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.top_rexxers_weekly(integer) TO service_role;