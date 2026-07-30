CREATE TABLE public.groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  name text NOT NULL,
  emoji text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, user_id)
);

CREATE TABLE public.group_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  recommendation_id uuid NOT NULL REFERENCES public.recommendations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, recommendation_id)
);

CREATE INDEX group_members_user_idx ON public.group_members(user_id);
CREATE INDEX group_shares_group_idx ON public.group_shares(group_id, created_at DESC);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.groups TO authenticated;
GRANT ALL ON public.groups TO service_role;
GRANT SELECT, INSERT, DELETE ON public.group_members TO authenticated;
GRANT ALL ON public.group_members TO service_role;
GRANT SELECT, INSERT, DELETE ON public.group_shares TO authenticated;
GRANT ALL ON public.group_shares TO service_role;

CREATE OR REPLACE FUNCTION public.is_group_member(_group uuid, _user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.group_members WHERE group_id = _group AND user_id = _user);
$$;

CREATE OR REPLACE FUNCTION public.is_group_owner(_group uuid, _user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.groups WHERE id = _group AND owner_id = _user);
$$;

REVOKE EXECUTE ON FUNCTION public.is_group_member(uuid, uuid) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.is_group_owner(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.is_group_member(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_group_owner(uuid, uuid) TO authenticated;

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_shares ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read groups" ON public.groups FOR SELECT TO authenticated
  USING (owner_id = auth.uid() OR public.is_group_member(id, auth.uid()));
CREATE POLICY "users create groups" ON public.groups FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY "owner updates group" ON public.groups FOR UPDATE TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY "owner deletes group" ON public.groups FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

CREATE POLICY "members read membership" ON public.group_members FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_group_member(group_id, auth.uid()) OR public.is_group_owner(group_id, auth.uid()));
CREATE POLICY "owner adds members" ON public.group_members FOR INSERT TO authenticated
  WITH CHECK (public.is_group_owner(group_id, auth.uid()));
CREATE POLICY "owner removes or member leaves" ON public.group_members FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR public.is_group_owner(group_id, auth.uid()));

CREATE POLICY "members read shares" ON public.group_shares FOR SELECT TO authenticated
  USING (public.is_group_member(group_id, auth.uid()) OR public.is_group_owner(group_id, auth.uid()));
CREATE POLICY "members create shares" ON public.group_shares FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND (public.is_group_member(group_id, auth.uid()) OR public.is_group_owner(group_id, auth.uid())));
CREATE POLICY "sharer or owner deletes share" ON public.group_shares FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR public.is_group_owner(group_id, auth.uid()));

CREATE TRIGGER groups_touch_updated_at BEFORE UPDATE ON public.groups
  FOR EACH ROW EXECUTE FUNCTION public.tg_touch_updated_at();