GRANT UPDATE ON public.saved_posts TO authenticated;
GRANT UPDATE ON public.wants TO authenticated;

CREATE POLICY "Users update own saves"
ON public.saved_posts FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id AND (list_id IS NULL OR public.can_edit_list(list_id, auth.uid()) OR public.can_view_list(list_id, auth.uid())));

CREATE POLICY "Collection editors can refile saved posts"
ON public.saved_posts FOR UPDATE TO authenticated
USING (list_id IS NOT NULL AND public.can_edit_list(list_id, auth.uid()))
WITH CHECK (list_id IS NULL OR public.can_edit_list(list_id, auth.uid()));

CREATE POLICY "Users update own wants"
ON public.wants FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id AND (list_id IS NULL OR public.can_edit_list(list_id, auth.uid()) OR public.can_view_list(list_id, auth.uid())));

CREATE POLICY "Collection editors can refile wants"
ON public.wants FOR UPDATE TO authenticated
USING (list_id IS NOT NULL AND public.can_edit_list(list_id, auth.uid()))
WITH CHECK (list_id IS NULL OR public.can_edit_list(list_id, auth.uid()));