
CREATE TABLE public.recommendation_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recommendation_id uuid NOT NULL REFERENCES public.recommendations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (recommendation_id, user_id)
);
GRANT SELECT, INSERT, DELETE ON public.recommendation_likes TO authenticated;
GRANT ALL ON public.recommendation_likes TO service_role;
ALTER TABLE public.recommendation_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "See likes on visible recommendations" ON public.recommendation_likes
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.recommendations r
      WHERE r.id = recommendation_likes.recommendation_id
        AND (r.user_id = auth.uid() OR public.are_friends(auth.uid(), r.user_id))
    )
  );
CREATE POLICY "Users insert own likes" ON public.recommendation_likes
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users delete own likes" ON public.recommendation_likes
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE INDEX idx_recommendation_likes_rec ON public.recommendation_likes(recommendation_id);

CREATE TABLE public.recommendation_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recommendation_id uuid NOT NULL REFERENCES public.recommendations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.recommendation_comments TO authenticated;
GRANT ALL ON public.recommendation_comments TO service_role;
ALTER TABLE public.recommendation_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "See comments on visible recommendations" ON public.recommendation_comments
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.recommendations r
      WHERE r.id = recommendation_comments.recommendation_id
        AND (r.user_id = auth.uid() OR public.are_friends(auth.uid(), r.user_id))
    )
  );
CREATE POLICY "Users insert own comments" ON public.recommendation_comments
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own comments" ON public.recommendation_comments
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users delete own comments" ON public.recommendation_comments
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE INDEX idx_recommendation_comments_rec ON public.recommendation_comments(recommendation_id, created_at);

CREATE TRIGGER trg_recommendation_comments_updated_at
  BEFORE UPDATE ON public.recommendation_comments
  FOR EACH ROW EXECUTE FUNCTION public.tg_touch_updated_at();
