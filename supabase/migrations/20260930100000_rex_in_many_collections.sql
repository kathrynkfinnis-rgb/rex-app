-- Sept 30 — "please can we make it that Rex can belong in more than one
-- collection".
--
-- They couldn't. saved_posts carried a unique constraint on
-- (user_id, recommendation_id), so one person could save a given Rex exactly
-- once — and since the collection is a column on that same row, saving it to
-- a second collection meant moving it out of the first. Nobody in the
-- database has the same Rex in two collections, because it was impossible.
--
-- The app has believed otherwise for a while: CollectionDetailView's drag
-- handler says "Dropping copies — a Rex can live in several lists", and the
-- drop silently did nothing when it collided with this constraint.
--
-- What the constraint should say is: not the same Rex twice in the SAME
-- collection. That's the thing worth preventing.

alter table public.saved_posts
  drop constraint if exists saved_posts_user_id_recommendation_id_key;

-- NULLS NOT DISTINCT is what makes this work for the un-filed case. A saved
-- Rex with no collection has list_id null, and under the default rule two
-- nulls never collide — so without this, "save" with no collection could
-- stack up duplicates. Postgres 15+; this project is on 17.
create unique index if not exists saved_posts_user_rec_list_key
  on public.saved_posts (user_id, recommendation_id, list_id) nulls not distinct;

comment on index public.saved_posts_user_rec_list_key is
  'One Rex may sit in many of your collections, but only once in each — and only once un-filed.';
