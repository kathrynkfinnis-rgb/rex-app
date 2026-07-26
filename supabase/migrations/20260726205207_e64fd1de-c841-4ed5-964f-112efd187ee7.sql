
ALTER FUNCTION public.tg_touch_updated_at() SET search_path = public;
REVOKE EXECUTE ON FUNCTION public.tg_touch_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.are_friends(UUID, UUID) FROM PUBLIC, anon;
-- are_friends is intentionally callable by authenticated (used in RLS policies via SECURITY DEFINER)
GRANT EXECUTE ON FUNCTION public.are_friends(UUID, UUID) TO authenticated;
