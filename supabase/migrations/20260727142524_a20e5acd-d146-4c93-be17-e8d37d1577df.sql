
CREATE TABLE public.creators (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  color TEXT NOT NULL,
  emoji TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.creators TO authenticated, anon;
GRANT ALL ON public.creators TO service_role;
ALTER TABLE public.creators ENABLE ROW LEVEL SECURITY;
CREATE POLICY "creators readable by all" ON public.creators FOR SELECT USING (true);

INSERT INTO public.creators (slug, name, color, emoji) VALUES
  ('rest-is-history', 'The Rest Is History', '#B7791F', '🏛️'),
  ('rest-is-politics', 'The Rest Is Politics', '#2563EB', '🗳️'),
  ('table-manners', 'Table Manners', '#DB2777', '🍽️'),
  ('rest-is-entertainment', 'The Rest Is Entertainment', '#9333EA', '🎬');

ALTER TABLE public.recommendations
  ADD COLUMN creator_id UUID REFERENCES public.creators(id) ON DELETE SET NULL;
CREATE INDEX idx_recommendations_creator_id ON public.recommendations(creator_id);
