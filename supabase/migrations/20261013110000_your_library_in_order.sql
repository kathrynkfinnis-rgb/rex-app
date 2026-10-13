-- Oct 13 — Joe, via Kathryn: "I would love to have my library of books in a
-- ranking order. So like Goodreads but better than a simple out of 5 stars.
-- Instead you rank it against your other books you have read. So you finish a
-- book and think ok that was better than The Harry Quebert Affair but not as
-- good as A Little Life, so it sits between them."
--
-- This is the right instinct and worth saying why. Five stars is useless for
-- ordering because everything good is a 4 or a 5: a scale that can't separate
-- the eleven books you'd call excellent isn't telling you what you asked.
-- Comparison is also how people actually hold preferences — nobody knows what
-- A Little Life is "out of ten", everybody knows whether it beat the last
-- thing they read.
--
-- ============================================================== the shape
-- A rank is a position in one person's ordering of one category. Not a score:
-- a score would have to be recomputed for everything each time something is
-- inserted, and the number would be meaningless on its own anyway.
--
-- Per category rather than one list for everything, because "better than" only
-- means something within a kind. A book against a restaurant is not a question.
create table if not exists public.rankings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  -- The category this ordering belongs to: 'book', 'movie', 'tv', 'place'…
  -- Stored rather than read through items so one query can fetch one ordering.
  category text not null,
  -- Position in that ordering, 1 = best. A float rather than an integer: an
  -- insertion between 4 and 5 becomes 4.5 and touches one row, where integers
  -- would renumber everything below it on every single insert. Rewritten to
  -- clean integers by rerank_* below when the gaps get small.
  position double precision not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, item_id)
);

create index if not exists rankings_user_category_idx
  on public.rankings (user_id, category, position);

grant select, insert, update, delete on public.rankings to authenticated;
grant all on public.rankings to service_role;

alter table public.rankings enable row level security;

-- Joe's whole point is that the ordering is worth showing other people — "v
-- useful for other people to see" — so friends can read it. Same visibility
-- rule as wants and ticket reminders.
drop policy if exists "See own and friends' rankings" on public.rankings;
create policy "See own and friends' rankings" on public.rankings
  for select to authenticated
  using (auth.uid() = user_id or public.are_friends(auth.uid(), user_id));

drop policy if exists "Users write own rankings" on public.rankings;
create policy "Users write own rankings" on public.rankings
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "Users change own rankings" on public.rankings;
create policy "Users change own rankings" on public.rankings
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users remove own rankings" on public.rankings;
create policy "Users remove own rankings" on public.rankings
  for delete to authenticated using (auth.uid() = user_id);

-- ====================================================== seeding an ordering
-- Nobody is going to rank two hundred books from nothing, and they don't have
-- to: there are already ratings on them. This lays the existing Rex out in
-- rating order as a starting point, so the first thing you see is roughly
-- right and every comparison after that improves it.
--
-- A seeded order is a guess and the app says so. The alternative — an empty
-- list and a demand to start comparing — is the version nobody finishes.
create or replace function public.seed_rankings(_category text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  seeded integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;

  with ordered as (
    select r.item_id,
           row_number() over (
             order by r.rating desc nulls last, r.created_at desc
           ) as rn
      from public.recommendations r
      join public.items i on i.id = r.item_id
     where r.user_id = auth.uid()
       and i.type = _category
       and r.trip_id is null
       -- A branch copy is not a book you read; see 20261013100000.
       and coalesce(r.is_branch_copy, false) = false
       and not exists (
         select 1 from public.rankings k
          where k.user_id = auth.uid() and k.item_id = r.item_id
       )
  )
  insert into public.rankings (user_id, item_id, category, position)
  select auth.uid(), ordered.item_id, _category,
         -- After anything already placed by hand, which outranks a guess.
         coalesce((select max(position) from public.rankings
                    where user_id = auth.uid() and category = _category), 0)
         + ordered.rn
    from ordered;

  get diagnostics seeded = row_count;
  return seeded;
end;
$$;

revoke all on function public.seed_rankings(text) from public, anon;
grant execute on function public.seed_rankings(text) to authenticated;

-- ======================================================= tidying the gaps
-- Repeated insertion between neighbours halves the gap each time, and a double
-- precision eventually runs out of room between 4.0 and 4.0000000000000004.
-- Renumbering to 1, 2, 3… costs one write per row and is only needed rarely,
-- so the app calls it when a gap gets too small rather than on a schedule.
create or replace function public.renumber_rankings(_category text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  touched integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;

  with ordered as (
    select id, row_number() over (order by position, updated_at) as rn
      from public.rankings
     where user_id = auth.uid() and category = _category
  )
  update public.rankings k
     set position = ordered.rn, updated_at = now()
    from ordered
   where k.id = ordered.id and k.position is distinct from ordered.rn;

  get diagnostics touched = row_count;
  return touched;
end;
$$;

revoke all on function public.renumber_rankings(text) from public, anon;
grant execute on function public.renumber_rankings(text) to authenticated;
