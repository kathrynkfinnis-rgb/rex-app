CREATE OR REPLACE FUNCTION public.search_profiles_for(_caller uuid, _query text, _limit integer DEFAULT 10)
RETURNS TABLE(id uuid, username text, display_name text, avatar_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.id, p.username, p.display_name, p.avatar_url
  FROM public.profiles p
  WHERE _caller IS NOT NULL
    AND p.id <> _caller
    AND length(btrim(_query)) >= 2
    AND p.username ILIKE '%' || btrim(_query) || '%'
  ORDER BY p.username ASC
  LIMIT LEAST(GREATEST(_limit, 1), 25);
$function$;

CREATE OR REPLACE FUNCTION public.suggested_friends_for(_caller uuid, _limit integer DEFAULT 20)
RETURNS TABLE(id uuid, username text, display_name text, avatar_url text, mutual_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH my_friends AS (
    SELECT CASE WHEN requester_id = _caller THEN addressee_id ELSE requester_id END AS friend_id
    FROM public.friendships
    WHERE status = 'accepted'
      AND (requester_id = _caller OR addressee_id = _caller)
  ),
  fof AS (
    SELECT CASE WHEN f.requester_id = mf.friend_id THEN f.addressee_id ELSE f.requester_id END AS candidate_id,
           mf.friend_id AS via
    FROM public.friendships f
    JOIN my_friends mf ON (f.requester_id = mf.friend_id OR f.addressee_id = mf.friend_id)
    WHERE f.status = 'accepted'
  ),
  filtered AS (
    SELECT candidate_id, COUNT(DISTINCT via) AS mutual_count
    FROM fof
    WHERE candidate_id <> _caller
      AND candidate_id NOT IN (SELECT friend_id FROM my_friends)
      AND NOT EXISTS (
        SELECT 1 FROM public.friendships f2
        WHERE (f2.requester_id = _caller AND f2.addressee_id = candidate_id)
           OR (f2.addressee_id = _caller AND f2.requester_id = candidate_id)
      )
    GROUP BY candidate_id
  )
  SELECT p.id, p.username, p.display_name, p.avatar_url, fl.mutual_count
  FROM filtered fl
  JOIN public.profiles p ON p.id = fl.candidate_id
  ORDER BY fl.mutual_count DESC, p.username ASC
  LIMIT _limit;
$function$;

REVOKE EXECUTE ON FUNCTION public.search_profiles_for(uuid, text, integer) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.suggested_friends_for(uuid, integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_profiles_for(uuid, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.suggested_friends_for(uuid, integer) TO service_role;

-- Remove the now-unused authenticated-facing wrappers to eliminate the linter warning
DROP FUNCTION IF EXISTS public.search_profiles(text, integer);
DROP FUNCTION IF EXISTS public.suggested_friends(integer);