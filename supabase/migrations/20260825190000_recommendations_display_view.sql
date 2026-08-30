-- #181 (security review, Aug 25) — "Post anonymously" (#78) only ever hid
-- the poster's identity in the app's own UI. The raw recommendations row
-- still carries the real user_id, and every read of it embeds the real
-- profiles row (username/display_name/avatar_url) alongside it — the
-- plain feed/friends SELECT policy and get_shared_recommendation() (used
-- for "share a Rex" links) both return it regardless of is_anonymous.
-- Anyone with API access to a row you can already legitimately see (a
-- friend, via curl + their own JWT, or a modified client; or anyone who
-- opens a share link) can read exactly who posted an "anonymous" Rex.
--
-- This view is the fix for the first of those two paths — the plain
-- feed/friends read. It's a 1:1 passthrough of every recommendations
-- column (so item_id/creator_id stay real, unmodified columns — the
-- items!inner(...)/creators(...) embeds PostgREST does today keep working
-- unchanged), except `profiles` is now a precomputed JSON object instead
-- of an automatic FK embed: null when the row is anonymous and you're not
-- its owner, the real {username,display_name,avatar_url} otherwise. That
-- swap is deliberate — masking the *embedded* resource with a CASE would
-- have broken PostgREST's relationship inference (which needs a plain,
-- unmodified FK column to trace), so this replaces the embed with a column
-- the client reads as plain JSON instead.
--
-- `security_invoker = true` is load-bearing, not optional: without it, a
-- plain view runs its underlying query as the view's owner for RLS
-- purposes, not the calling user — which would mean this view proceeds to
-- reveal every user's recommendations to every other authenticated user,
-- a much worse hole than the one it's fixing. With it, recommendations'
-- own "own and friends'" RLS policy is enforced exactly as if the client
-- had queried the base table directly, so this view can only ever narrow
-- what's already visible, never widen it.
--
-- get_shared_recommendation() (the share-link path) gets its own matching
-- fix below since it's a separate, already-existing SECURITY DEFINER
-- function, not something read through this view.
CREATE OR REPLACE VIEW public.recommendations_display
WITH (security_invoker = true) AS
SELECT
  r.id,
  r.user_id,
  r.item_id,
  r.rating,
  r.note,
  r.photo_url,
  r.photo_urls,
  r.tags,
  r.created_at,
  r.updated_at,
  r.trip_id,
  r.trip_section,
  r.list_id,
  r.list_section,
  r.show_in_feed,
  r.published_at,
  r.creator_id,
  r.is_anonymous,
  CASE
    WHEN r.is_anonymous AND r.user_id <> auth.uid() THEN NULL::jsonb
    ELSE jsonb_build_object(
      'username', p.username,
      'display_name', p.display_name,
      'avatar_url', p.avatar_url
    )
  END AS profiles
FROM public.recommendations r
LEFT JOIN public.profiles p ON p.id = r.user_id;

GRANT SELECT ON public.recommendations_display TO authenticated;

-- get_shared_recommendation() — same masking, applied directly since this
-- is a flat SQL function already, no embed/view mechanics involved. A
-- share link to an anonymous Rex now hands back a null author rather than
-- the real one.
CREATE OR REPLACE FUNCTION public.get_shared_recommendation(rec_id uuid)
RETURNS TABLE (
  id uuid,
  rating int,
  note text,
  created_at timestamptz,
  photo_url text,
  photo_urls text[],
  item_id uuid,
  item_type text,
  item_title text,
  item_subtitle text,
  item_image_url text,
  item_genre text,
  author_username text,
  author_display_name text,
  author_avatar_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    r.id,
    r.rating,
    r.note,
    r.created_at,
    r.photo_url,
    r.photo_urls,
    i.id AS item_id,
    i.type::text AS item_type,
    i.title AS item_title,
    i.subtitle AS item_subtitle,
    i.image_url AS item_image_url,
    i.genre AS item_genre,
    CASE WHEN r.is_anonymous THEN NULL ELSE p.username END AS author_username,
    CASE WHEN r.is_anonymous THEN NULL ELSE p.display_name END AS author_display_name,
    CASE WHEN r.is_anonymous THEN NULL ELSE p.avatar_url END AS author_avatar_url
  FROM public.recommendations r
  JOIN public.items i ON i.id = r.item_id
  LEFT JOIN public.profiles p ON p.id = r.user_id
  WHERE r.id = rec_id
  LIMIT 1;
$$;
