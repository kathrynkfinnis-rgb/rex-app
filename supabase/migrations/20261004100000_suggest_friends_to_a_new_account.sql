-- Oct 4 — "we need to consider how potential friends are recommended to a
-- user upon sign up."
--
-- suggested_friends_for_me is friends-of-friends and nothing else, so for
-- somebody who has just signed up it returns zero rows. Their first sight of
-- REX is the find-friends step with nothing in it, followed by an empty feed —
-- which for an app that is entirely other people is the worst possible first
-- impression, and the exact moment someone decides whether to bother.
--
-- The fix is a second tier, used only to fill the space friends-of-friends
-- leaves: the accounts with the most recommendations to their name. For a
-- private app where the people worth following are the ones who have actually
-- put things in, "who has Rex'd the most" is a better opening answer than
-- nothing, and it degrades sensibly as the network grows, because the
-- friend-of-friend tier crowds it out on its own.
--
-- No new exposure: every profile here is already reachable through
-- search_profiles, which any signed-in user can call. This changes which
-- profiles are put in front of someone, not which ones they could find.
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
  -- Anyone already connected to me in any state: a friend, a request I have
  -- sent, or one I have been sent. None of them belong in "people you might
  -- know", and a pending request reappearing as a suggestion reads as though
  -- the app has forgotten you asked.
  related AS (
    SELECT CASE WHEN requester_id = auth.uid() THEN addressee_id ELSE requester_id END AS other_id
    FROM public.friendships
    WHERE requester_id = auth.uid() OR addressee_id = auth.uid()
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
      AND candidate_id NOT IN (SELECT other_id FROM related)
    GROUP BY candidate_id
  ),
  -- The top-up. Ordered by how much someone has actually contributed, so a
  -- new account is pointed at people whose feed is worth having.
  active AS (
    SELECT r.user_id AS candidate_id, 0::bigint AS mutual_count, COUNT(*) AS rex_count
    FROM public.recommendations r
    WHERE r.user_id <> auth.uid()
      AND r.user_id NOT IN (SELECT other_id FROM related)
      AND r.user_id NOT IN (SELECT candidate_id FROM filtered)
      AND r.trip_id IS NULL
      AND r.list_id IS NULL
    GROUP BY r.user_id
  ),
  ranked AS (
    SELECT candidate_id, mutual_count, 0 AS tier, NULL::bigint AS rex_count FROM filtered
    UNION ALL
    SELECT candidate_id, mutual_count, 1 AS tier, rex_count FROM active
  )
  SELECT p.id, p.username, p.display_name, p.avatar_url, rk.mutual_count
  FROM ranked rk
  JOIN public.profiles p ON p.id = rk.candidate_id
  -- Friends-of-friends always first, then the most active, then alphabetical
  -- so the list is stable between loads rather than reshuffling.
  ORDER BY rk.tier ASC, rk.mutual_count DESC, rk.rex_count DESC NULLS LAST, p.username ASC
  LIMIT _limit;
$function$;

REVOKE EXECUTE ON FUNCTION public.suggested_friends_for_me(integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.suggested_friends_for_me(integer) TO authenticated;
