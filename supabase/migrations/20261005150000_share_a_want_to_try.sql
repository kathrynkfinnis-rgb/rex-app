-- Oct 5 — "want to be able to send 'want to try' via WhatsApp."
--
-- Every other kind of Rex has had a share link since #177; a want didn't,
-- and the share icon was deliberately hidden on want cards rather than hand
-- out a link to a page that didn't exist. This is that page's data.
--
-- A want has no rating and no note — it is someone saying they'd like to try
-- this — so the shared page is the thing itself plus who wants to try it,
-- and nothing is invented to fill the gap where a review would be.
--
-- SECURITY DEFINER for the same reason get_shared_recommendation is: a share
-- link is opened by whoever it was sent to, who is usually not signed in and
-- is not the sender's friend. The wants policy ("own and friends'") would
-- refuse them, which is the whole point of having a function instead.
--
-- Sharing is the owner's decision, so this deliberately does not consult
-- show_in_feed: keeping something out of the feed is not the same as keeping
-- it from the friend you are sending it to. It returns only what the person
-- sharing already chose to send.
CREATE OR REPLACE FUNCTION public.get_shared_want(want_id uuid)
RETURNS TABLE (
  id uuid,
  created_at timestamptz,
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
    w.id,
    w.created_at,
    w.photo_urls,
    i.id AS item_id,
    i.type::text AS item_type,
    i.title AS item_title,
    i.subtitle AS item_subtitle,
    i.image_url AS item_image_url,
    i.genre AS item_genre,
    p.username AS author_username,
    p.display_name AS author_display_name,
    p.avatar_url AS author_avatar_url
  FROM public.wants w
  JOIN public.items i ON i.id = w.item_id
  LEFT JOIN public.profiles p ON p.id = w.user_id
  WHERE w.id = want_id
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_shared_want(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shared_want(uuid) TO anon, authenticated;

COMMENT ON FUNCTION public.get_shared_want(uuid) IS
  'One want-to-try for its public share page, by id. The want''s counterpart to get_shared_recommendation — no rating and no note, because a want has neither.';
