ALTER TYPE public.item_type ADD VALUE IF NOT EXISTS 'trip';

ALTER TABLE public.recommendations
  ADD COLUMN IF NOT EXISTS trip_id uuid REFERENCES public.recommendations(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS recommendations_trip_id_idx ON public.recommendations(trip_id);