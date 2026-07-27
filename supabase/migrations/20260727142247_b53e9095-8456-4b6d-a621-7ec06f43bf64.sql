
CREATE OR REPLACE FUNCTION public.suggested_friends(_limit int DEFAULT 20)
RETURNS TABLE (id uuid, username text, display_name text, avatar_url text, mutual_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

GRANT EXECUTE ON FUNCTION public.suggested_friends(int) TO authenticated;
