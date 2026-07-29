
CREATE TABLE public.hitlist_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_type text NOT NULL,
  name text NOT NULL,
  emoji text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX hitlist_lists_user_idx ON public.hitlist_lists(user_id, item_type);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hitlist_lists TO authenticated;
GRANT ALL ON public.hitlist_lists TO service_role;
ALTER TABLE public.hitlist_lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own hitlist_lists" ON public.hitlist_lists
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

ALTER TABLE public.wants ADD COLUMN list_id uuid REFERENCES public.hitlist_lists(id) ON DELETE SET NULL;
ALTER TABLE public.saved_posts ADD COLUMN list_id uuid REFERENCES public.hitlist_lists(id) ON DELETE SET NULL;
CREATE INDEX wants_list_idx ON public.wants(list_id);
CREATE INDEX saved_posts_list_idx ON public.saved_posts(list_id);
