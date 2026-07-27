
-- 1. Tighten profiles SELECT policy
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;

CREATE POLICY "Profiles viewable by self, friends, and pending connections"
ON public.profiles
FOR SELECT
TO authenticated
USING (
  auth.uid() = id
  OR public.are_friends(auth.uid(), id)
  OR EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE (f.requester_id = auth.uid() AND f.addressee_id = profiles.id)
       OR (f.addressee_id = auth.uid() AND f.requester_id = profiles.id)
  )
);

-- 2. SECURITY DEFINER helper for username search (bypasses tightened RLS,
--    returns only public basics)
CREATE OR REPLACE FUNCTION public.search_profiles(_query text, _limit int DEFAULT 10)
RETURNS TABLE(id uuid, username text, display_name text, avatar_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.username, p.display_name, p.avatar_url
  FROM public.profiles p
  WHERE auth.uid() IS NOT NULL
    AND p.id <> auth.uid()
    AND length(btrim(_query)) >= 2
    AND p.username ILIKE '%' || btrim(_query) || '%'
  ORDER BY p.username ASC
  LIMIT LEAST(GREATEST(_limit, 1), 25);
$$;

-- 3. Lock down EXECUTE on SECURITY DEFINER functions
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tg_touch_updated_at() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.are_friends(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.are_friends(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.suggested_friends(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.suggested_friends(integer) TO authenticated;

REVOKE ALL ON FUNCTION public.search_profiles(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_profiles(text, integer) TO authenticated;
