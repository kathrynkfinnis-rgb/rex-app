CREATE TABLE public.wants (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_id uuid NOT NULL REFERENCES public.items(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, item_id)
);

GRANT SELECT, INSERT, DELETE ON public.wants TO authenticated;
GRANT ALL ON public.wants TO service_role;

ALTER TABLE public.wants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "See own and friends' wants" ON public.wants
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.are_friends(auth.uid(), user_id));

CREATE POLICY "Users insert own wants" ON public.wants
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users delete own wants" ON public.wants
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

CREATE INDEX wants_user_created_idx ON public.wants(user_id, created_at DESC);
CREATE INDEX wants_item_idx ON public.wants(item_id);