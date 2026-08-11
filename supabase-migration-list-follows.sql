-- Run in Supabase Dashboard → SQL Editor → New query → Run.
--
-- Following someone's collection (read-only) is distinct from collaborating
-- on one (list_collaborators, co-editing). This adds the follow side.

create table if not exists public.list_follows (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  list_id uuid not null references public.hitlist_lists(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, list_id)
);

alter table public.list_follows enable row level security;

-- You manage your own follows, and can only see your own.
create policy "Users can view their own follows"
  on public.list_follows for select to authenticated
  using (user_id = auth.uid());

create policy "Users can follow lists"
  on public.list_follows for insert to authenticated
  with check (user_id = auth.uid());

create policy "Users can unfollow lists"
  on public.list_follows for delete to authenticated
  using (user_id = auth.uid());

create index if not exists list_follows_user_id_idx on public.list_follows (user_id);
create index if not exists list_follows_list_id_idx on public.list_follows (list_id);
