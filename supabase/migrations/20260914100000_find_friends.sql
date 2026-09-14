-- Sept 14 — "When Danny logged in, he wasn't asked to create a username.
-- Also, he has no way to search for friends... Need to also be able to look
-- at your friends' friends as another way to find users." And: "build the
-- find friends through contacts".
--
-- Four pieces, all for the same job — a new person finding the people they
-- know.

-- ============================================================ 1. search
-- search_profiles() doesn't exist in production. It was created on 27 July,
-- dropped a few migrations later (20260727152002, in favour of a
-- service-role-only search_profiles_for that the native app can't call),
-- and the migration that recreated it (20260820190000) was never run. So
-- the app's friend search has been calling a missing function since July,
-- getting a 404, and showing an empty result — nobody could find anyone
-- they weren't already connected to.
--
-- Recreated here with its grant stated explicitly rather than left to
-- default privileges, which is how it got lost last time.
create or replace function public.search_profiles(_query text, _limit int default 10)
returns table(id uuid, username text, display_name text, avatar_url text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.avatar_url
  from public.profiles p
  where auth.uid() is not null
    and p.id <> auth.uid()
    and length(btrim(_query)) >= 2
    and (
      p.username ilike '%' || btrim(_query) || '%'
      or p.display_name ilike '%' || btrim(_query) || '%'
    )
  order by
    -- Exact and prefix matches first: typing "dan" should put @danny above
    -- @jordan.
    (lower(p.username) = lower(btrim(_query))) desc,
    (p.username ilike btrim(_query) || '%' or p.display_name ilike btrim(_query) || '%') desc,
    p.username asc
  limit least(greatest(_limit, 1), 25);
$$;

revoke all on function public.search_profiles(text, int) from public, anon;
grant execute on function public.search_profiles(text, int) to authenticated;

-- ============================================================ 2. friends of a friend
-- "Look at your friends' friends." Opening a friend's profile lists their
-- friends, so you can add the ones you know.
--
-- Security definer because profiles and friendships are both RLS-limited to
-- your own connections — but only answers for someone you're actually
-- friends with (or yourself). A stranger's friend list stays private.
--
-- `connection` is the caller's own relationship to each person listed, so
-- the app can show Add / Requested / Friends / You without a second trip.
create or replace function public.friends_of(_user uuid, _limit int default 200)
returns table(id uuid, username text, display_name text, avatar_url text, connection text)
language sql
stable
security definer
set search_path = public
as $$
  with allowed as (
    select 1
    where auth.uid() is not null
      and (_user = auth.uid() or public.are_friends(auth.uid(), _user))
  ),
  their_friends as (
    select case when f.requester_id = _user then f.addressee_id else f.requester_id end as friend_id
    from public.friendships f, allowed
    where f.status = 'accepted'
      and (f.requester_id = _user or f.addressee_id = _user)
  )
  select p.id, p.username, p.display_name, p.avatar_url,
    case
      when p.id = auth.uid() then 'you'
      when exists (
        select 1 from public.friendships m
        where m.status = 'accepted'
          and ((m.requester_id = auth.uid() and m.addressee_id = p.id)
            or (m.addressee_id = auth.uid() and m.requester_id = p.id))
      ) then 'friend'
      when exists (
        select 1 from public.friendships m
        where m.status = 'pending' and m.requester_id = auth.uid() and m.addressee_id = p.id
      ) then 'requested'
      when exists (
        select 1 from public.friendships m
        where m.status = 'pending' and m.addressee_id = auth.uid() and m.requester_id = p.id
      ) then 'requested_you'
      else 'none'
    end as connection
  from their_friends t
  join public.profiles p on p.id = t.friend_id
  order by coalesce(p.display_name, p.username)
  limit least(greatest(_limit, 1), 500);
$$;

revoke all on function public.friends_of(uuid, int) from public, anon;
grant execute on function public.friends_of(uuid, int) to authenticated;

-- ============================================================ 3. contacts
-- Find friends through your phone's contacts. The app never sends anyone's
-- email address: it sends SHA-256 hashes of the (lower-cased, trimmed)
-- emails in your contacts, and gets back the Rex profiles whose sign-in
-- email hashes to one of them. Nothing is stored.
--
-- Capped at 2,000 hashes a call — enough for any real address book, and a
-- ceiling on anyone trying to use this to test whether a long list of
-- guessed addresses are on Rex.
create or replace function public.match_contact_emails(_hashes text[])
returns table(id uuid, username text, display_name text, avatar_url text, connection text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select p.id, p.username, p.display_name, p.avatar_url,
    case
      when exists (
        select 1 from public.friendships m
        where m.status = 'accepted'
          and ((m.requester_id = auth.uid() and m.addressee_id = p.id)
            or (m.addressee_id = auth.uid() and m.requester_id = p.id))
      ) then 'friend'
      when exists (
        select 1 from public.friendships m
        where m.status = 'pending' and m.requester_id = auth.uid() and m.addressee_id = p.id
      ) then 'requested'
      when exists (
        select 1 from public.friendships m
        where m.status = 'pending' and m.addressee_id = auth.uid() and m.requester_id = p.id
      ) then 'requested_you'
      else 'none'
    end as connection
  from auth.users u
  join public.profiles p on p.id = u.id
  where auth.uid() is not null
    and u.id <> auth.uid()
    and u.email is not null
    and coalesce(array_length(_hashes, 1), 0) <= 2000
    and encode(extensions.digest(lower(btrim(u.email)), 'sha256'), 'hex') = any(_hashes)
  order by coalesce(p.display_name, p.username);
$$;

revoke all on function public.match_contact_emails(text[]) from public, anon;
grant execute on function public.match_contact_emails(text[]) to authenticated;

-- ============================================================ 4. usernames
-- New accounts get a username made from their email ("dannyo83", or a
-- string of letters for a hidden Apple email) and were never asked about
-- it — which is also what friends search looks for, so a bad one makes you
-- hard to find. The app now asks anyone whose username isn't confirmed.
--
-- Everyone who joined before the first external testers (5 Sept) keeps
-- theirs as it is — Kathryn, Gemma and Phoebe chose theirs on the web.
-- Anyone since gets asked once.
alter table public.profiles
  add column if not exists username_confirmed boolean not null default false;

update public.profiles
set username_confirmed = true
where created_at < '2026-09-05'
  and username_confirmed = false;
