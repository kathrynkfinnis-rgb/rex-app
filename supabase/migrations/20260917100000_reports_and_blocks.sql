-- Sept 17 — reporting offensive content, and blocking people.
--
-- Both are App Store requirements for any app with user-generated content
-- (Guideline 1.2): a way to report content, a way to block abusive users,
-- and a commitment to act on reports within 24 hours. They're also just
-- the right thing to have before more people join.

-- ============================================================ reports
create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  -- What's being reported. Kept as a loose (kind, id) pair rather than a
  -- foreign key per kind: a report should survive the thing it's about
  -- being deleted, which is often the outcome we want.
  target_kind text not null check (target_kind in ('recommendation', 'comment', 'blast', 'blast_reply', 'list', 'trip', 'profile', 'photo')),
  target_id uuid not null,
  -- Who posted it, when we know — so repeat offenders are visible without
  -- having to chase each report back to its content.
  target_user_id uuid references auth.users(id) on delete set null,
  reason text not null check (reason in ('spam', 'harassment', 'hate', 'sexual', 'violence', 'self_harm', 'misinformation', 'impersonation', 'intellectual_property', 'other')),
  detail text,
  status text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewer_note text
);

create index if not exists content_reports_status_idx on public.content_reports (status, created_at desc);
create index if not exists content_reports_target_idx on public.content_reports (target_user_id, created_at desc);

alter table public.content_reports enable row level security;

drop policy if exists "report what you can see" on public.content_reports;
create policy "report what you can see" on public.content_reports
  for insert to authenticated with check (reporter_id = auth.uid());

-- You can see your own reports (so the app can say "you reported this");
-- admins see everything, to act on them.
drop policy if exists "read own reports, admins read all" on public.content_reports;
create policy "read own reports, admins read all" on public.content_reports
  for select to authenticated
  using (reporter_id = auth.uid() or public.has_role(auth.uid(), 'admin'));

drop policy if exists "admins resolve reports" on public.content_reports;
create policy "admins resolve reports" on public.content_reports
  for update to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

grant select, insert on public.content_reports to authenticated;
grant update on public.content_reports to authenticated;
grant all on public.content_reports to service_role;

-- ============================================================ blocks
create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;

-- Only ever your own list, in both directions of reading: nobody is told
-- they've been blocked.
drop policy if exists "manage your own blocks" on public.user_blocks;
create policy "manage your own blocks" on public.user_blocks
  for all to authenticated
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

grant select, insert, delete on public.user_blocks to authenticated;
grant all on public.user_blocks to service_role;

-- Blocking removes any friendship or pending request in either direction —
-- a block that leaves you still friends isn't a block. Security definer
-- because the row belongs to both people.
create or replace function public.block_user(_blocked uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;
  if me = _blocked then raise exception 'You can''t block yourself'; end if;

  insert into public.user_blocks (blocker_id, blocked_id)
  values (me, _blocked)
  on conflict do nothing;

  delete from public.friendships
  where (requester_id = me and addressee_id = _blocked)
     or (requester_id = _blocked and addressee_id = me);

  -- Their notifications about you, and yours about them, go too.
  delete from public.notifications
  where (user_id = me and actor_id = _blocked)
     or (user_id = _blocked and actor_id = me);
end;
$$;

revoke all on function public.block_user(uuid) from public, anon;
grant execute on function public.block_user(uuid) to authenticated;

-- The ids to leave out of a feed, map or search: everyone you've blocked,
-- and everyone who has blocked you (they shouldn't see you either).
create or replace function public.hidden_user_ids()
returns table(user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select blocked_id from public.user_blocks where blocker_id = auth.uid()
  union
  select blocker_id from public.user_blocks where blocked_id = auth.uid();
$$;

revoke all on function public.hidden_user_ids() from public, anon;
grant execute on function public.hidden_user_ids() to authenticated;
