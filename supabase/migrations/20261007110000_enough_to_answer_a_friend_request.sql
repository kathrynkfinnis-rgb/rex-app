-- Oct 7 — "this was the page when I clicked on Eibhlin's friend request,
-- please can we make it better. Have her name at the top! And then maybe the
-- date joined, how many Rexes etc."
--
-- The name landed in build 72 (profile_basics, 5 October). This is the rest:
-- enough about somebody to answer a friend request without having to accept
-- one to find out who they are.
--
-- Two numbers and a date, and nothing else. How long they've been here, how
-- much they've posted, and how many friends — the questions you actually ask
-- about a stranger's account. Deliberately NOT what they Rex'd: that is the
-- thing being friends is for, and showing it here would make the friendship
-- pointless rather than make the decision easier.
--
-- The counts are totals rather than "mutual friends", which would be the more
-- useful number but also tells you about other people's friend lists. A count
-- of somebody's own activity is theirs to show; a count derived from who else
-- they know is not clearly theirs to give away.
-- Dropped rather than replaced: this adds three columns to the return type,
-- and CREATE OR REPLACE cannot change one ("cannot change return type of
-- existing function"). Nothing depends on it at the database level — the app
-- calls it over PostgREST — so dropping and recreating costs nothing beyond
-- the instant between the two statements.
DROP FUNCTION IF EXISTS public.profile_basics(uuid[]);

CREATE OR REPLACE FUNCTION public.profile_basics(_ids uuid[])
RETURNS TABLE(
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  joined_at timestamptz,
  rex_count bigint,
  friend_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.created_at AS joined_at,
    (
      SELECT count(*)
      FROM public.recommendations r
      JOIN public.items i ON i.id = r.item_id
      WHERE r.user_id = p.id
        -- A trip's own container row is not a Rex, it is the thing the stops
        -- hang off, so counting it would overstate everybody by one per trip.
        AND i.type::text NOT IN ('trip', 'list')
    ) AS rex_count,
    (
      SELECT count(*)
      FROM public.friendships f
      WHERE f.status = 'accepted'
        AND (f.requester_id = p.id OR f.addressee_id = p.id)
    ) AS friend_count
  FROM public.profiles p
  WHERE auth.uid() IS NOT NULL
    AND p.id = ANY(_ids)
    -- Someone who blocked you doesn't appear, the same as everywhere else.
    AND NOT EXISTS (
      SELECT 1 FROM public.user_blocks b
      WHERE b.blocker_id = p.id AND b.blocked_id = auth.uid()
    )
  LIMIT 200;
$$;

REVOKE ALL ON FUNCTION public.profile_basics(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.profile_basics(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.profile_basics(uuid[]) IS
  'Who somebody is, by id, plus how long they have been here and how much they have posted — enough to answer a friend request. The four name columns are the same ones search_profiles has returned to any signed-in user since July.';
