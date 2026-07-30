ALTER TABLE public.feedback ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.feedback ADD COLUMN IF NOT EXISTS is_anonymous boolean NOT NULL DEFAULT false;

DROP POLICY IF EXISTS "users read own feedback" ON public.feedback;
CREATE POLICY "users read own feedback"
  ON public.feedback FOR SELECT
  TO authenticated
  USING ((user_id IS NOT NULL AND auth.uid() = user_id) OR has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "users insert own feedback" ON public.feedback;
CREATE POLICY "users insert own feedback"
  ON public.feedback FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id AND is_anonymous = false);