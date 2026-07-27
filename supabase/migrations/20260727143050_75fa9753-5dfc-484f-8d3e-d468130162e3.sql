create table public.creator_follows (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  creator_id uuid not null references public.creators(id) on delete cascade,
  created_at timestamp with time zone not null default now(),
  unique (user_id, creator_id)
);

grant select, insert, delete on public.creator_follows to authenticated;
grant all on public.creator_follows to service_role;

alter table public.creator_follows enable row level security;

create policy "Users see own follows"
on public.creator_follows
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users follow creators"
on public.creator_follows
for insert
to authenticated
with check (auth.uid() = user_id);

create policy "Users unfollow creators"
on public.creator_follows
for delete
to authenticated
using (auth.uid() = user_id);

-- Allow users to see recommendations from creators they follow
create policy "See recommendations from followed creators"
on public.recommendations
for select
to authenticated
using (
  exists (
    select 1 from public.creator_follows cf
    where cf.user_id = auth.uid()
      and cf.creator_id = recommendations.creator_id
  )
);