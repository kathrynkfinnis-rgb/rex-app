
DROP POLICY IF EXISTS "Collaborators can see shared lists" ON public.hitlist_lists;
CREATE POLICY "Collaborators can see shared lists" ON public.hitlist_lists
FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.list_collaborators c WHERE c.list_id = hitlist_lists.id AND c.user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.can_view_list(_list uuid, _user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.hitlist_lists l
    WHERE l.id = _list
      AND (
        l.user_id = _user
        OR l.visibility = 'public'
        OR (l.visibility = 'friends' AND public.are_friends(_user, l.user_id))
        OR EXISTS (SELECT 1 FROM public.list_collaborators c WHERE c.list_id = l.id AND c.user_id = _user)
      )
  )
$$;

REVOKE ALL ON FUNCTION public.can_view_list(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_list(uuid, uuid) TO authenticated, service_role;

CREATE POLICY "See items in visible lists" ON public.wants
FOR SELECT TO authenticated
USING (list_id IS NOT NULL AND public.can_view_list(list_id, auth.uid()));

CREATE POLICY "See saved posts in visible lists" ON public.saved_posts
FOR SELECT TO authenticated
USING (list_id IS NOT NULL AND public.can_view_list(list_id, auth.uid()));
