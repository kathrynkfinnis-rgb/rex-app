-- Oct 22 — "let's make the shareable wish list."
--
-- The second half of "buy my want to reads". The first half put a cart on
-- each row of your own list so you can buy from it. This is the half where
-- you hand the list to somebody else before a birthday and they buy from it.
--
-- Same shape as get_shared_ranking, deliberately: keyed by whose and which,
-- because a wish list is not one row with an id — it is everything you have
-- said you want in a category. Security definer so the page can read it
-- without a session, which is the whole point of a link you can send.
--
-- What it will not return:
--
--   * A want the owner hid from the feed. show_in_feed false means they
--     chose to keep it to themselves, and a public page is the opposite of
--     that. Absent or true both show, matching every other query on wants.
--   * Anything for a category Amazon has nothing to sell for. A shared list
--     of places is a different feature and this is not it.
--   * Anything at all if the user has no wants in that category, which the
--     page turns into a 404 rather than an empty list — an empty page tells
--     a stranger that the person exists.
--
-- Deliberately public to anyone holding the link, matching the ranking
-- pages. A want-to-read list is a list of books somebody fancies; the
-- sensitive thing in REX is who your friends are, and this exposes none of
-- that. If that judgement changes, the fix is a privacy column on the owner
-- rather than a change here.
--
-- Nov 1 — items.type is an enum (item_type), not text, so every comparison
-- and the select itself need ::text. Without the casts Postgres refuses the
-- first one and would have refused the other two in turn.

create or replace function public.get_shared_wishlist(_user uuid, _category text)
returns table (
  owner_username text,
  owner_display_name text,
  item_title text,
  item_subtitle text,
  item_image_url text,
  item_type text,
  wanted_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.username,
    p.display_name,
    i.title,
    i.subtitle,
    i.image_url,
    i.type::text,
    w.created_at
  from public.wants w
  join public.items i on i.id = w.item_id
  join public.profiles p on p.id = w.user_id
  where w.user_id = _user
    and i.type::text = _category
    -- Only what Amazon could sell. A shared list of places or trips is a
    -- different feature; offering a buy link against one would be a lie.
    and i.type::text in ('book', 'movie', 'tv', 'other')
    and coalesce(w.show_in_feed, true)
  order by w.created_at desc
  limit 200;
$$;

revoke all on function public.get_shared_wishlist(uuid, text) from public;
-- anon is the point: the page is read by somebody who has not installed REX.
grant execute on function public.get_shared_wishlist(uuid, text) to anon, authenticated;

comment on function public.get_shared_wishlist(uuid, text) is
  'One person''s want-to-try list in one category, for the public page at find-rex.com/l/<user>/<category>. Excludes wants hidden from the feed.';
