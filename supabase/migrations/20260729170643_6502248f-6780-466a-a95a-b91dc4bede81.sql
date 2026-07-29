CREATE TABLE public.requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type item_type,
  title text NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.requests TO authenticated;
GRANT ALL ON public.requests TO service_role;

ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "See own and friends' requests" ON public.requests
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.are_friends(auth.uid(), user_id));
CREATE POLICY "Users insert own requests" ON public.requests
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own requests" ON public.requests
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users delete own requests" ON public.requests
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE TRIGGER requests_touch_updated_at
  BEFORE UPDATE ON public.requests
  FOR EACH ROW EXECUTE FUNCTION public.tg_touch_updated_at();

CREATE TABLE public.request_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body text NOT NULL,
  suggested_item_id uuid REFERENCES public.items(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.request_comments TO authenticated;
GRANT ALL ON public.request_comments TO service_role;

ALTER TABLE public.request_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "See comments on visible requests" ON public.request_comments
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.requests r
    WHERE r.id = request_comments.request_id
      AND (r.user_id = auth.uid() OR public.are_friends(auth.uid(), r.user_id))
  ));
CREATE POLICY "Users insert comments on visible requests" ON public.request_comments
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.requests r
      WHERE r.id = request_comments.request_id
        AND (r.user_id = auth.uid() OR public.are_friends(auth.uid(), r.user_id))
    )
  );
CREATE POLICY "Users update own request comments" ON public.request_comments
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users delete own request comments" ON public.request_comments
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE TRIGGER request_comments_touch_updated_at
  BEFORE UPDATE ON public.request_comments
  FOR EACH ROW EXECUTE FUNCTION public.tg_touch_updated_at();

CREATE INDEX requests_user_created_idx ON public.requests(user_id, created_at DESC);
CREATE INDEX request_comments_request_created_idx ON public.request_comments(request_id, created_at ASC);