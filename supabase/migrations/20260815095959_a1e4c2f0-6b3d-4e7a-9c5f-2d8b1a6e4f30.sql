-- Trip stops have optional ratings (0 = unrated, see DraftStop.rating in the
-- native app and task #43 "Make trip stop ratings optional"). The check
-- constraint was never updated to allow that sentinel, so posting a trip
-- with any unrated stop violates recommendations_rating_check and the whole
-- trip fails to post. This just adds the 0 case alongside the existing
-- 1-10 range; nothing else about the column changes.
ALTER TABLE public.recommendations DROP CONSTRAINT recommendations_rating_check;
ALTER TABLE public.recommendations ADD CONSTRAINT recommendations_rating_check
  CHECK (rating = 0 OR (rating >= 1 AND rating <= 10));
