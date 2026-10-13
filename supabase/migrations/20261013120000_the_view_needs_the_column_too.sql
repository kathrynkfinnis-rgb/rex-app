-- Oct 13 — "feed is broken in latest update."
--
-- It was, and by my hand. 20261013100000 added is_branch_copy to the
-- recommendations table and the app began filtering the feed on it. The feed
-- does not read the table: it reads recommendations_display, the view that
-- masks an anonymous poster's profile. The view selects its columns by name,
-- so it carried on returning the set it was written with in August and knew
-- nothing about the new one.
--
-- The app has a probe for exactly this — name a column PostgREST doesn't know
-- and it rejects the whole query, so check first. The probe asked
-- /rest/v1/recommendations while the query asked
-- /rest/v1/recommendations_display. The table had the column, the view did
-- not, the probe said yes, and every feed request came back
-- `column recommendations_display.is_branch_copy does not exist`.
--
-- The view, with one column added and nothing else touched. The app-side
-- probe now asks whichever resource it is about to query, so a view lagging
-- behind its table degrades to showing branch copies rather than showing
-- nothing.
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
  END AS profiles,
  -- Last, not in its natural place beside is_anonymous: CREATE OR REPLACE
  -- VIEW can only append columns, and inserting one mid-list reads as
  -- renaming every column after it — "cannot change name of view column
  -- \"profiles\" to \"is_branch_copy\"", which is what it said when I tried.
  -- Order is nothing to the app, which names every column it selects.
  r.is_branch_copy
FROM public.recommendations r
LEFT JOIN public.profiles p ON p.id = r.user_id;

GRANT SELECT ON public.recommendations_display TO authenticated;
