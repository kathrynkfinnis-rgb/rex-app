-- Fix creator-follow leak: drop the overbroad policy
DROP POLICY IF EXISTS "See recommendations from followed creators" ON public.recommendations;

-- Switch are_friends to SECURITY INVOKER (auth.uid() is always one side, so RLS on friendships permits it)
CREATE OR REPLACE FUNCTION public.are_friends(_a uuid, _b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.friendships
    WHERE status = 'accepted'
      AND ((requester_id = _a AND addressee_id = _b)
        OR (requester_id = _b AND addressee_id = _a))
  );
$function$;

-- Revoke signed-in EXECUTE on remaining SECURITY DEFINER RPCs; call via service role from server functions
REVOKE EXECUTE ON FUNCTION public.search_profiles(text, integer) FROM authenticated, anon, public;
REVOKE EXECUTE ON FUNCTION public.suggested_friends(integer) FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.search_profiles(text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.suggested_friends(integer) TO service_role;