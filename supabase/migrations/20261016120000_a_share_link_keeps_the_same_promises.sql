-- Oct 16, security review — F19 and F29.
--
-- The share functions are capability URLs: holding the id is the permission.
-- That is a deliberate design and a defensible one. What is not defensible is
-- that each of them makes different promises about the same data.
--
-- `get_shared_recommendation` masks an anonymous author (25 Aug). Its three
-- siblings — trip, trip stops, and collection items — select the author's
-- username and display name unconditionally, to `anon`, on the open internet.
-- So marking a post anonymous works until it is a stop on a trip or sits in
-- a public collection, at which point your name is on it again. The app gives
-- no hint that those are different privacy regimes, because they shouldn't be.
--
-- Two more gaps in the same family:
--
--   * None of them filters `published_at`. The 15 August migration says RLS on
--     that column "is the only thing that actually guarantees a draft can't
--     leak through some fetch path that forgot to filter" — and a SECURITY
--     DEFINER function bypasses RLS, so these are exactly that path. Drafts
--     and the official account's scheduled queue are readable by id.
--
--   * `get_shared_want` ignores `show_in_feed`. Somebody who explicitly chose
--     "keep it off the feed" still has that want served to anyone with the
--     link. A capability URL is a fair deal; overriding the user's own hide
--     flag is not part of it.
--
-- If any of these columns turns out not to exist in production this migration
-- will say so and change nothing — which, after today, is the failure mode I
-- want. Two of the three have already disagreed with the files.

-- ─────────────────────────────────────────────────────────────────────
-- Trips
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.get_shared_trip(_trip uuid)
returns table(
  id uuid, rating integer, note text, created_at timestamptz,
  photo_url text, photo_urls text[],
  item_id uuid, item_title text, item_subtitle text, item_image_url text,
  author_username text, author_display_name text, author_avatar_url text
)
language sql stable security definer set search_path to 'public'
as $$
  select r.id, r.rating, r.note, r.created_at, r.photo_url, r.photo_urls,
         i.id, i.title, i.subtitle, i.image_url,
         case when r.is_anonymous then null else p.username end,
         case when r.is_anonymous then null else p.display_name end,
         case when r.is_anonymous then null else p.avatar_url end
  from public.recommendations r
  join public.items i on i.id = r.item_id
  left join public.profiles p on p.id = r.user_id
  where r.id = _trip
    and i.type = 'trip'
    and r.published_at is not null
  limit 1;
$$;

create or replace function public.get_shared_trip_stops(_trip uuid)
returns table(
  id uuid, rating integer, note text, created_at timestamptz,
  photo_url text, photo_urls text[],
  item_id uuid, item_type text, item_title text, item_subtitle text,
  item_image_url text, item_genre text, item_address text,
  item_lat double precision, item_lng double precision,
  author_username text, author_display_name text, author_avatar_url text
)
language sql stable security definer set search_path to 'public'
as $$
  select r.id, r.rating, r.note, r.created_at, r.photo_url, r.photo_urls,
         i.id, i.type::text, i.title, i.subtitle, i.image_url, i.genre,
         i.address, i.lat, i.lng,
         case when r.is_anonymous then null else p.username end,
         case when r.is_anonymous then null else p.display_name end,
         case when r.is_anonymous then null else p.avatar_url end
  from public.recommendations r
  join public.items i on i.id = r.item_id
  left join public.profiles p on p.id = r.user_id
  where r.trip_id = _trip
    and r.published_at is not null
  order by r.created_at asc;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Collection items
--
-- The `l.visibility = 'public'` join stays — that is this function's access
-- control and it is correct. What is added is the author masking, and the
-- published filter so a draft saved into a public collection isn't published
-- by someone else's collection setting.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.get_shared_collection_items(_list uuid)
returns table(
  recommendation_id uuid, rating integer, note text,
  item_id uuid, item_type text, item_title text, item_subtitle text,
  item_image_url text, item_genre text, item_address text,
  author_username text, author_display_name text,
  section text, sort_order integer
)
language sql stable security definer set search_path to 'public'
as $$
  select r.id, r.rating, r.note,
         i.id, i.type, i.title, i.subtitle, i.image_url, i.genre, i.address,
         case when r.is_anonymous then null else p.username end,
         case when r.is_anonymous then null else p.display_name end,
         sp.section, sp.sort_order
  from public.saved_posts sp
  join public.hitlist_lists l on l.id = sp.list_id and l.visibility = 'public'
  join public.recommendations r on r.id = sp.recommendation_id
  join public.items i on i.id = r.item_id
  left join public.profiles p on p.id = r.user_id
  where sp.list_id = _list
    and r.published_at is not null
  order by sp.sort_order nulls last, sp.created_at;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Wants
--
-- Honours the author's own hide flag. `show_in_feed` is null for every want
-- written before that column existed and for anything that never touched the
-- toggle, so `is not false` is the right test — absent and true both share,
-- only an explicit false withholds. That is the same reading the feed uses.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.get_shared_want(want_id uuid)
returns table (
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
language sql stable security definer set search_path = public
as $$
  select w.id, w.created_at, w.photo_urls,
         i.id, i.type::text, i.title, i.subtitle, i.image_url, i.genre,
         p.username, p.display_name, p.avatar_url
  from public.wants w
  join public.items i on i.id = w.item_id
  left join public.profiles p on p.id = w.user_id
  where w.id = want_id
    and w.show_in_feed is not false
  limit 1;
$$;

comment on function public.get_shared_trip is
  'Capability URL: the id is the permission. Masks an anonymous author and refuses unpublished drafts, which get_shared_recommendation has done since 25 August and this had not.';
