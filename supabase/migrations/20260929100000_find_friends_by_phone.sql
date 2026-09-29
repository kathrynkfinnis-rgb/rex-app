-- Sept 29 — "please ask for phone number at sign up" so contacts matching
-- can work on numbers as well as emails.
--
-- The number itself is never stored. What's kept is a SHA-256 hash of it in
-- E.164 form (+447917004798), which is exactly what the app already sends for
-- emails: enough to recognise a number someone already has in their phone,
-- useless for finding out anyone's number who you don't.
--
-- Worth being clear about what that does and doesn't protect. A hash of a
-- phone number is not a secret — the space of UK mobiles is small enough to
-- enumerate — so this is not a promise that a stolen database reveals
-- nothing. It's a promise that REX itself never holds a list of its users'
-- phone numbers, that nothing is sent anywhere in the clear, and that a
-- leaked row is a hash rather than a number. The 2,000-per-call ceiling is
-- what stops the matching endpoint being used to enumerate.

alter table public.profiles
  add column if not exists phone_sha256 text;

comment on column public.profiles.phone_sha256 is
  'SHA-256 of the E.164 phone number, for contact matching only. The number itself is never stored.';

-- Only one account per number: two people claiming the same phone means one
-- of them typed it wrong, and matching would send both to whoever searched.
create unique index if not exists profiles_phone_sha256_idx
  on public.profiles (phone_sha256) where phone_sha256 is not null;

-- ============================================================ matching
-- The phone twin of match_contact_emails, and deliberately identical in
-- shape: same cap, same connection labels, same ordering.
create or replace function public.match_contact_phones(_hashes text[])
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
  from public.profiles p
  where auth.uid() is not null
    and p.id <> auth.uid()
    and p.phone_sha256 is not null
    and coalesce(array_length(_hashes, 1), 0) <= 2000
    and p.phone_sha256 = any(_hashes)
  order by coalesce(p.display_name, p.username);
$$;

revoke all on function public.match_contact_phones(text[]) from public, anon;
grant execute on function public.match_contact_phones(text[]) to authenticated;

-- ============================================================ saving yours
-- Setting it goes through a function rather than a column update so the
-- uniqueness clash reads as a sentence rather than a Postgres error, and so
-- nobody can write a hash onto somebody else's row.
create or replace function public.set_my_phone_hash(_hash text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;

  if _hash is null or length(btrim(_hash)) = 0 then
    update public.profiles set phone_sha256 = null where id = me;
    return;
  end if;

  if exists (select 1 from public.profiles where phone_sha256 = _hash and id <> me) then
    raise exception 'That number is already on another REX account.';
  end if;

  update public.profiles set phone_sha256 = _hash where id = me;
end;
$$;

revoke all on function public.set_my_phone_hash(text) from public, anon;
grant execute on function public.set_my_phone_hash(text) to authenticated;
