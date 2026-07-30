CREATE OR REPLACE FUNCTION public.search_profiles_for(_caller uuid, _query text, _limit integer DEFAULT 10)
RETURNS TABLE(id uuid, username text, display_name text, avatar_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.username, p.display_name, p.avatar_url
  FROM public.profiles p
  WHERE _caller IS NOT NULL
    AND length(btrim(_query)) >= 2
    AND (p.username ILIKE '%' || btrim(_query) || '%'
         OR coalesce(p.display_name, '') ILIKE '%' || btrim(_query) || '%')
  ORDER BY (p.id = _caller) DESC, p.username ASC
  LIMIT LEAST(GREATEST(_limit, 1), 25);
$$;
REVOKE ALL ON FUNCTION public.search_profiles_for(uuid, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_profiles_for(uuid, text, integer) TO service_role;