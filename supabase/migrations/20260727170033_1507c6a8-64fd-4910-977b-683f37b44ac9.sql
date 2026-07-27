CREATE TABLE public.import_staging (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  source text NOT NULL,
  raw_title text NOT NULL,
  raw_creator text,
  raw_note text,
  raw_rating numeric,
  suggested_type item_type,
  resolved_item_id uuid REFERENCES public.items(id) ON DELETE SET NULL,
  resolved_external_id text,
  resolved_external_source text,
  resolved_image_url text,
  resolved_subtitle text,
  resolved_genre text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.import_staging TO authenticated;
GRANT ALL ON public.import_staging TO service_role;

ALTER TABLE public.import_staging ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own staging select" ON public.import_staging
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "own staging insert" ON public.import_staging
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "own staging update" ON public.import_staging
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "own staging delete" ON public.import_staging
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE TRIGGER trg_import_staging_updated
  BEFORE UPDATE ON public.import_staging
  FOR EACH ROW EXECUTE FUNCTION public.tg_touch_updated_at();

CREATE INDEX idx_import_staging_user_status ON public.import_staging(user_id, status, created_at DESC);