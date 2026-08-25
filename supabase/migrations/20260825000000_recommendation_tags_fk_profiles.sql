-- Fixes a real bug in the previous migration (recommendation_tags), caught
-- live as "Couldn't load your feed (400)" immediately after it ran.
--
-- recommendation_tags.user_id was created referencing auth.users(id) — but
-- every embed in this app that reaches profiles (RexAPI.fetchFeed's
-- `recommendation_tags(profiles(...))`, matching the same
-- `profiles!recommendations_user_id_fkey` pattern used everywhere else)
-- needs PostgREST to see a *direct* foreign key from the tag row to
-- public.profiles — a shared FK to auth.users on both sides isn't
-- something PostgREST infers a relationship through. With no direct FK,
-- PostgREST can't resolve the embed at all, and 400s the entire query —
-- not just the new tags field, the whole feed.
ALTER TABLE public.recommendation_tags
  DROP CONSTRAINT recommendation_tags_user_id_fkey;

ALTER TABLE public.recommendation_tags
  ADD CONSTRAINT recommendation_tags_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
