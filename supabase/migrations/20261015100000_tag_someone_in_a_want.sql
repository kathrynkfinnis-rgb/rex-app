-- Oct 15 — "also need to be able to tag someone in a want to try."
--
-- You can tag friends on a Rex (#162, 22 Aug) and not on a want, and the
-- reason is structural rather than deliberate: recommendation_tags references
-- recommendations, and a want is a row in `wants` with no recommendation
-- behind it. The same split already produced want_likes and want_comments, so
-- this is the third of that family and built to match them exactly.
--
-- It is arguably the more useful half. "Went here with Phoebe" is a fact you
-- record afterwards; "shall we go, Phoebe?" is the whole point of writing a
-- want down, and until now there was no way to say it to anybody.
create table if not exists public.want_tags (
  want_id uuid not null references public.wants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (want_id, user_id)
);

create index if not exists want_tags_user_idx on public.want_tags(user_id);

grant select, insert, delete on public.want_tags to authenticated;
grant all on public.want_tags to service_role;

alter table public.want_tags enable row level security;

-- Same visibility as recommendation_tags: a tag is shown on the card, it is
-- not a secret.
drop policy if exists "Want tags are visible to anyone" on public.want_tags;
create policy "Want tags are visible to anyone" on public.want_tags
  for select to authenticated using (true);

-- Only whoever wrote the want can tag or untag people on it.
drop policy if exists "Author tags people on own want" on public.want_tags;
create policy "Author tags people on own want" on public.want_tags
  for insert to authenticated with check (
    exists (
      select 1 from public.wants w
      where w.id = want_id and w.user_id = auth.uid()
    )
  );

drop policy if exists "Author untags people from own want" on public.want_tags;
create policy "Author untags people from own want" on public.want_tags
  for delete to authenticated using (
    exists (
      select 1 from public.wants w
      where w.id = want_id and w.user_id = auth.uid()
    )
  );

-- The notification, under the same preference as being tagged on a Rex —
-- somebody who has turned that off has turned this off. entity_type 'want' is
-- the one the app already resolves to a want's page (see linkedWantId), so
-- tapping it lands where it should without anything new client-side.
create or replace function public.tg_notify_want_tagged()
returns trigger language plpgsql security definer set search_path = public as $$
declare actor uuid;
begin
  select user_id into actor from public.wants where id = new.want_id;
  if actor is null or actor = new.user_id then return new; end if;
  if not public.notif_pref_enabled(new.user_id, 'rec_tagged') then return new; end if;

  insert into public.notifications (user_id, actor_id, type, entity_type, entity_id)
  values (new.user_id, actor, 'want_tagged', 'want', new.want_id);
  return new;
end;
$$;

drop trigger if exists notify_want_tagged on public.want_tags;
create trigger notify_want_tagged after insert on public.want_tags
  for each row execute function public.tg_notify_want_tagged();

comment on table public.want_tags is
  'Friends tagged on a want-to-try — "shall we go?". The wants half of recommendation_tags.';
