-- #128 — search_profiles() (added 20260727142816 to bypass the tightened
-- profiles RLS policy for search) only ever matched p.username, not
-- p.display_name. The native app was calling neither (it hit the RLS-
-- blocked direct select instead, fixed separately) — now that it calls
-- this RPC, a real name like "Kathryn" not turning up because her
-- searchable username is unrelated is the next thing that would bite.
-- Same idempotent CREATE OR REPLACE pattern as the original.
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
    AND (
      p.username ILIKE '%' || btrim(_query) || '%'
      OR p.display_name ILIKE '%' || btrim(_query) || '%'
    )
  ORDER BY p.username ASC
  LIMIT LEAST(GREATEST(_limit, 1), 25);
$$;
