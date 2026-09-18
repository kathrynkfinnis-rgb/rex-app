-- Sept 18 — "start building a Rex profile, that we can start automatically
-- posting recommendations to keep the feed interesting."
--
-- The shape Kathryn picked: REX is a real account that everyone is friends
-- with from the moment they sign up (so its Rex arrive through the ordinary
-- feed, and anyone can unfriend it exactly like a person), and its posts come
-- from a queue the three admins fill by hand and a scheduled job drips out.
--
-- Almost none of this is new machinery. A queued post is just a draft — a
-- recommendation with published_at NULL, which RLS already hides from
-- everyone but its author — plus a date saying when to publish it. The job
-- sets published_at. Nothing in the app has to know a scheduled post exists.

-- ============================================ the account itself
alter table public.profiles
  add column if not exists is_official boolean not null default false;

comment on column public.profiles.is_official is
  'The REX account itself. Everyone is auto-friended with it at sign-up.';

-- Exactly one, so the rest of this file can say "the official account"
-- without ambiguity.
create unique index if not exists profiles_one_official_idx
  on public.profiles (is_official) where is_official;

create or replace function public.official_account_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.profiles where is_official limit 1;
$$;

revoke all on function public.official_account_id() from public, anon;
grant execute on function public.official_account_id() to authenticated;

-- ============================================ everyone is friends with REX
-- Friendship rows belong to both people, so this can't be done from the
-- client under RLS — hence security definer, and hence a trigger rather than
-- a call the app has to remember to make.
create or replace function public.befriend_official_account(_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare official uuid := public.official_account_id();
begin
  if official is null or official = _user then return; end if;

  insert into public.friendships (requester_id, addressee_id, status)
  values (official, _user, 'accepted')
  on conflict do nothing;
end;
$$;

revoke all on function public.befriend_official_account(uuid) from public, anon;

create or replace function public.tg_befriend_official_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.befriend_official_account(new.id);
  return new;
end;
$$;

drop trigger if exists befriend_official_on_profile on public.profiles;
create trigger befriend_official_on_profile
  after insert on public.profiles
  for each row execute function public.tg_befriend_official_account();

-- ============================================ the queue
-- When a queued Rex should go out. NULL on every ordinary row — a person's
-- draft has no schedule, it publishes when they press the button.
alter table public.recommendations
  add column if not exists scheduled_at timestamptz;

create index if not exists recommendations_scheduled_idx
  on public.recommendations (scheduled_at)
  where published_at is null and scheduled_at is not null;

-- Admins post as REX. The existing insert policy is "user_id = auth.uid()",
-- which is right for everyone else and has to stay exactly as strict: this
-- adds one narrow exception rather than loosening it.
drop policy if exists "admins post as the official account" on public.recommendations;
create policy "admins post as the official account" on public.recommendations
  for insert to authenticated
  with check (
    public.has_role(auth.uid(), 'admin')
    and user_id = public.official_account_id()
  );

drop policy if exists "admins manage the official account's posts" on public.recommendations;
create policy "admins manage the official account's posts" on public.recommendations
  for update to authenticated
  using (public.has_role(auth.uid(), 'admin') and user_id = public.official_account_id())
  with check (public.has_role(auth.uid(), 'admin') and user_id = public.official_account_id());

-- Admins need to see the queue — which is a pile of drafts belonging to
-- someone else, and so invisible to them under the policy above.
drop policy if exists "admins read the official account's queue" on public.recommendations;
create policy "admins read the official account's queue" on public.recommendations
  for select to authenticated
  using (public.has_role(auth.uid(), 'admin') and user_id = public.official_account_id());

-- ============================================ the drip
-- Publishes anything queued whose time has come, and returns how many went
-- out so a caller (or a human running it by hand) can see it worked.
create or replace function public.publish_due_official_posts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare official uuid := public.official_account_id();
        published integer;
begin
  if official is null then return 0; end if;

  with due as (
    update public.recommendations
       set published_at = now()
     where user_id = official
       and published_at is null
       and scheduled_at is not null
       and scheduled_at <= now()
    returning id
  )
  select count(*) into published from due;

  return published;
end;
$$;

revoke all on function public.publish_due_official_posts() from public, anon;
grant execute on function public.publish_due_official_posts() to service_role;

-- Every quarter of an hour: close enough that a queued post goes out roughly
-- when it was meant to, rare enough to be invisible.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('publish-rex-queue')
      where exists (select 1 from cron.job where jobname = 'publish-rex-queue');
    perform cron.schedule(
      'publish-rex-queue', '*/15 * * * *',
      $cron$select public.publish_due_official_posts();$cron$
    );
  end if;
end;
$$;
