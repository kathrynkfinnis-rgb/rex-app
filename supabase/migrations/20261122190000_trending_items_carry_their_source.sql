-- Explore thumbnails: everything the shelf needs to stop showing the wrong
-- picture, a blurry one, or none at all.
--
-- The shelves showed items.image_url and nothing else. That one fact
-- explains all three faults: trips have no catalogue picture so they fell
-- through to a grey bag glyph; products and events have no catalogue behind
-- them at all, so whatever somebody uploaded became the item's official
-- image (Operation Mincemeat a screenshot with app UI in it, two different
-- car seat products sharing one photo of a Volvo seat); and those photos
-- were never meant to be thumbnails, so they blur when scaled into one.
--
-- Four columns, answering the four options Kathryn picked:
--
--   external_source  (C) tell catalogue art from a camera roll
--   rex_photos       (D) a mosaic where several people Rex'd the same thing
--   trip_photos      (A) a trip's cover, taken from its own stops
--   trip_lats/lngs   (A) and a map of those stops when it has no photos
--
-- On C, the signal matters and the obvious one does not work. The plan was
-- to test where the image is hosted — ours or someone else's. That fails,
-- because repairPlacePhotoIfNeeded COPIES a Google Place photo into our
-- bucket, through the very same uploadPhoto() a person's own camera roll
-- goes through, landing at the same rec-photos/<user-id>/<uuid>.jpg. By URL
-- the two are identical. external_source survives: set when the item came
-- from a lookup (Google for a place, TMDB for a film, Open Library for a
-- book), null when somebody typed the thing in by hand — which is exactly
-- the case that produces a bad thumbnail. A shop's own product shot keeps
-- its picture; a hand-typed item with an upload does not.
--
-- On A, "default to a hero photo if there is one, but if none, then map."
-- A trip's row carries no pictures of its own; they are on its stops, one
-- per place somebody actually went. So the stops are where both the cover
-- and the map come from, and the same stop list serves whichever is used.
--
-- PRIVACY. This function is readable signed-out — Explore's Rexperts tab is
-- editorial content and has been public since 1 October (App Store guideline
-- 5.1.1(v)). The promise made at the time was that it returns item facts and
-- a count, never who recommended anything. A count is not personal; a
-- photograph someone took, and the coordinates of places they went, plainly
-- are. So the four new photo and coordinate columns come back NULL to an
-- anonymous caller, and the tiles fall back to catalogue art or a title.
-- external_source is not gated: that a place came from Google is a fact
-- about the place, visible to anyone looking at it.
--
-- The return type changes, so it has to be dropped rather than replaced.

drop function if exists public.trending_items_weekly(integer);

create function public.trending_items_weekly(_limit integer default 10)
returns table(
  item_id uuid,
  title text,
  subtitle text,
  image_url text,
  type text,
  rex_count bigint,
  external_source text,
  rex_photos text[],
  trip_photos text[],
  trip_lats double precision[],
  trip_lngs double precision[]
)
language sql
stable
security definer
set search_path = public
as $$
  with top as (
    select i.id, i.title, i.subtitle, i.image_url, i.type, i.external_source,
           count(r.id) as rex_count
    from public.recommendations r
    join public.items i on i.id = r.item_id
    where r.created_at >= now() - interval '7 days'
      and r.trip_id is null
      and r.published_at is not null
    group by i.id, i.title, i.subtitle, i.image_url, i.type, i.external_source
    order by count(r.id) desc, i.title asc
    limit greatest(1, least(coalesce(_limit, 10), 30))
  )
  select
    t.id,
    t.title,
    t.subtitle,
    t.image_url,
    t.type,
    t.rex_count,
    t.external_source,
    case when auth.uid() is null then null else rp.photos end,
    case when auth.uid() is null then null else tp.photos end,
    case when auth.uid() is null then null else tp.lats end,
    case when auth.uid() is null then null else tp.lngs end
  from top t

  -- (D) Up to four distinct photographs of this thing, newest first. The
  -- shelf is called "most Rex'd" and one person's picture undersells that.
  left join lateral (
    select array_agg(photo) as photos
    from (
      select a.photo
      from (
        select unnest(
                 case
                   when coalesce(array_length(r2.photo_urls, 1), 0) > 0 then r2.photo_urls
                   when r2.photo_url is not null then array[r2.photo_url]
                   else array[]::text[]
                 end
               ) as photo,
               r2.created_at
        from public.recommendations r2
        where r2.item_id = t.id
          and r2.published_at is not null
          and r2.trip_id is null
        order by r2.created_at desc
        limit 8
      ) a
      where a.photo is not null and a.photo <> ''
      group by a.photo
      order by max(a.created_at) desc
      limit 4
    ) b
  ) rp on true

  -- (A) A trip's own stops: their photographs for the cover, their
  -- coordinates for the map that stands in when there are none. Both come
  -- from one pass over the stops, in the order they were added.
  left join lateral (
    select
      (select array_agg(photo)
       from (
         select c.photo
         from (
           select unnest(
                    case
                      when coalesce(array_length(s.photo_urls, 1), 0) > 0 then s.photo_urls
                      when s.photo_url is not null then array[s.photo_url]
                      else array[]::text[]
                    end
                  ) as photo,
                  s.created_at
           from public.recommendations trip_rec
           join public.recommendations s on s.trip_id = trip_rec.id
           where trip_rec.item_id = t.id
             and trip_rec.published_at is not null
             and s.published_at is not null
           order by s.created_at asc
           limit 12
         ) c
         where c.photo is not null and c.photo <> ''
         group by c.photo
         order by min(c.created_at) asc
         limit 4
       ) d
      ) as photos,
      (select array_agg(lat order by ord) from (
         select si.lat, row_number() over (order by s.created_at asc) as ord
         from public.recommendations trip_rec
         join public.recommendations s on s.trip_id = trip_rec.id
         join public.items si on si.id = s.item_id
         where trip_rec.item_id = t.id
           and trip_rec.published_at is not null
           and s.published_at is not null
           and si.lat is not null and si.lng is not null
         limit 20
       ) e) as lats,
      (select array_agg(lng order by ord) from (
         select si.lng, row_number() over (order by s.created_at asc) as ord
         from public.recommendations trip_rec
         join public.recommendations s on s.trip_id = trip_rec.id
         join public.items si on si.id = s.item_id
         where trip_rec.item_id = t.id
           and trip_rec.published_at is not null
           and s.published_at is not null
           and si.lat is not null and si.lng is not null
         limit 20
       ) f) as lngs
    where t.type = 'trip'
  ) tp on true

  order by t.rex_count desc, t.title asc
$$;

-- Same grants the dropped function carried.
revoke all on function public.trending_items_weekly(integer) from public, anon;
grant execute on function public.trending_items_weekly(integer) to authenticated;
grant execute on function public.trending_items_weekly(integer) to service_role;
grant execute on function public.trending_items_weekly(integer) to anon;

comment on function public.trending_items_weekly(integer) is
  'Most-Rex''d items of the last 7 days. Readable signed-out (App Store 5.1.1(v)); returns item facts and a count only, never who recommended them. Photos and trip coordinates are returned only to a signed-in caller. external_source lets the client tell catalogue art from a camera-roll photo, which the image URL cannot.';
