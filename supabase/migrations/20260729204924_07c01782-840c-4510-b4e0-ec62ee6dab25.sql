ALTER TABLE public.recommendations ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}'::text[];
CREATE INDEX IF NOT EXISTS recommendations_tags_gin ON public.recommendations USING gin (tags);