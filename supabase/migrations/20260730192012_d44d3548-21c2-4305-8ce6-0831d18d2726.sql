CREATE TABLE public.top_friends (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  friend_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE (user_id, friend_id),
  CHECK (user_id <> friend_id)
);

CREATE INDEX top_friends_user_idx ON public.top_friends (user_id);

GRANT SELECT, INSERT, DELETE ON public.top_friends TO authenticated;
GRANT ALL ON public.top_friends TO service_role;

ALTER TABLE public.top_friends ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Owners can view their own top friends"
ON public.top_friends FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Owners can add top friends they are friends with"
ON public.top_friends FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid() AND public.are_friends(auth.uid(), friend_id));

CREATE POLICY "Owners can remove their own top friends"
ON public.top_friends FOR DELETE TO authenticated
USING (user_id = auth.uid());