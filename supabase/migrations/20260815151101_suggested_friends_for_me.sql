-- Expose "suggested friends" (friends-of-friends, ranked by mutual count)
-- directly to the native app via PostgREST RPC.
--
-- The existing public.suggested_friends_for(_caller uuid, _limit int) is
-- locked down to service_role only (see migration 20260727152002) — safe
-- when the only caller was the web app's own service-role server function,
-- but NOT safe to grant to `authenticated` as-is: any signed-in user could
-- pass a different _caller and read someone else's mutual-friend graph.
--
-- This adds a second function with the same query logic but no _caller
-- parameter — it reads auth.uid() internally instead, the same way RLS
-- policies do, so a caller can only ever get their own suggestions. Native
-- calls this one; the web app's service-role path is untouched.
CREATE OR REPLACE FUNCTION public.suggested_friends_for_me(_limit integer DEFAULT 20)
RETURNS TABLE(id uuid, username text, display_name text, avatar_url text, mutual_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH my_friends AS (
    SELECT CASE WHEN requester_id = auth.uid() THEN addressee_id ELSE requester_id END AS friend_id
    FROM public.friendships
    WHERE status = 'accepted'
      AND (requester_id = auth.uid() OR addressee_id = auth.uid())
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
    WHERE candidate_id <> auth.uid()
      AND candidate_id NOT IN (SELECT friend_id FROM my_friends)
      AND NOT EXISTS (
        SELECT 1 FROM public.friendships f2
        WHERE (f2.requester_id = auth.uid() AND f2.addressee_id = candidate_id)
           OR (f2.addressee_id = auth.uid() AND f2.requester_id = candidate_id)
      )
    GROUP BY candidate_id
  )
  SELECT p.id, p.username, p.display_name, p.avatar_url, fl.mutual_count
  FROM filtered fl
  JOIN public.profiles p ON p.id = fl.candidate_id
  ORDER BY fl.mutual_count DESC, p.username ASC
  LIMIT _limit;
$function$;

REVOKE EXECUTE ON FUNCTION public.suggested_friends_for_me(integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.suggested_friends_for_me(integer) TO authenticated;
