
CREATE TABLE public.list_collaborators (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id uuid NOT NULL REFERENCES public.hitlist_lists(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  added_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (list_id, user_id)
);

GRANT SELECT, INSERT, DELETE ON public.list_collaborators TO authenticated;
GRANT ALL ON public.list_collaborators TO service_role;

ALTER TABLE public.list_collaborators ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_list_owner(_list uuid, _user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.hitlist_lists l WHERE l.id = _list AND l.user_id = _user);
$$;

CREATE OR REPLACE FUNCTION public.can_edit_list(_list uuid, _user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT _list IS NOT NULL AND _user IS NOT NULL AND (
    EXISTS (SELECT 1 FROM public.hitlist_lists l WHERE l.id = _list AND l.user_id = _user)
    OR EXISTS (SELECT 1 FROM public.list_collaborators c WHERE c.list_id = _list AND c.user_id = _user)
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_list_owner(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.can_edit_list(uuid, uuid) FROM anon;

CREATE POLICY "Collaborators and owner can see collaborators"
  ON public.list_collaborators FOR SELECT TO authenticated
  USING (public.can_edit_list(list_id, auth.uid()));

CREATE POLICY "List owner can add collaborators"
  ON public.list_collaborators FOR INSERT TO authenticated
  WITH CHECK (public.is_list_owner(list_id, auth.uid()) AND added_by = auth.uid());

CREATE POLICY "Owner removes collaborators, collaborator can leave"
  ON public.list_collaborators FOR DELETE TO authenticated
  USING (public.is_list_owner(list_id, auth.uid()) OR user_id = auth.uid());

CREATE POLICY "Collaborators can see shared lists"
  ON public.hitlist_lists FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.list_collaborators c WHERE c.list_id = id AND c.user_id = auth.uid()));

CREATE POLICY "Collaborators see items in shared lists"
  ON public.wants FOR SELECT TO authenticated
  USING (list_id IS NOT NULL AND public.can_edit_list(list_id, auth.uid()));

CREATE POLICY "List owner can remove shared want items"
  ON public.wants FOR DELETE TO authenticated
  USING (list_id IS NOT NULL AND public.is_list_owner(list_id, auth.uid()));

CREATE POLICY "Collaborators see saved posts in shared lists"
  ON public.saved_posts FOR SELECT TO authenticated
  USING (list_id IS NOT NULL AND public.can_edit_list(list_id, auth.uid()));

CREATE POLICY "List owner can remove shared saved posts"
  ON public.saved_posts FOR DELETE TO authenticated
  USING (list_id IS NOT NULL AND public.is_list_owner(list_id, auth.uid()));
