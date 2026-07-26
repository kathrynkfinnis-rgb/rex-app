ALTER TABLE public.recommendations DROP CONSTRAINT recommendations_rating_check;
ALTER TABLE public.recommendations ADD CONSTRAINT recommendations_rating_check CHECK (rating >= 1 AND rating <= 10);
UPDATE public.recommendations SET rating = LEAST(10, rating * 2);