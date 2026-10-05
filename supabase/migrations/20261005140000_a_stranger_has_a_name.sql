-- Oct 5 — "why would this be the page for trying to request a new friend."
--
-- Opening a stranger's profile showed no name, no username and no avatar:
-- a blank circle, the literal word "Profile" as the title, and an Add friend
-- button. You were being asked to decide whether to send a friend request to
-- somebody the page would not identify.
--
-- The cause is the profiles SELECT policy from 20260727142816, which limits
-- the table to yourself, your friends, and anyone you already have a
-- friendship row with. A stranger is none of those, so the row simply isn't
-- returned — 200 OK, empty array, no error to notice. This is the same shape
-- of bug as #128, where username search came back empty for exactly the
-- people you were searching for.
--
-- That migration's own answer to this was search_profiles(), a SECURITY
-- DEFINER function returning id, username, display_name and avatar_url to any
-- authenticated user who types two characters. So those four columns are
-- already public to everyone signed in; what follows exposes nothing new, it
-- just lets you look one up by id instead of by guessing their username.
--
-- Deliberately only those four columns. Everything else a profile holds —
-- email, counts, settings — stays behind the policy, because the question
-- this answers is "who am I about to add", not "show me this person".
CREATE OR REPLACE FUNCTION public.profile_basics(_ids uuid[])
RETURNS TABLE(id uuid, username text, display_name text, avatar_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.username, p.display_name, p.avatar_url
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
  'Name, username and avatar for any signed-in user, by id. The same four columns search_profiles already returns to anyone who types a username — this is the lookup-by-id counterpart, so a stranger''s profile page can say who they are.';
