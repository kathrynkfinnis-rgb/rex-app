-- Sept 5 — "for 'want to's, we still need to be able to like and comment".
--
-- A want isn't a recommendation: it lives in `wants` (user_id + item_id),
-- with no row in `recommendations` at all. Both `likes` and
-- `recommendation_comments` are keyed by recommendation_id with a real
-- foreign key, so there was nowhere to put a like on a want — which is why
-- the app hid those two icons on want cards rather than showing buttons
-- that silently failed.
--
-- Two parallel tables rather than making recommendation_id nullable, or
-- giving every want a shadow recommendation row: both of those change how
-- existing, working data is shaped, and neither is reversible in a hurry.
-- These are purely additive.

create table if not exists public.want_likes (
  id uuid primary key default gen_random_uuid(),
  want_id uuid not null references public.wants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (want_id, user_id)
);

create table if not exists public.want_comments (
  id uuid primary key default gen_random_uuid(),
  want_id uuid not null references public.wants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists want_likes_want_idx on public.want_likes (want_id);
create index if not exists want_comments_want_idx on public.want_comments (want_id, created_at);

alter table public.want_likes enable row level security;
alter table public.want_comments enable row level security;

-- Visibility follows the want itself: if you can see the want, you can see
-- what people said about it. Anything stricter would show a comment count
-- that didn't match the comments.
drop policy if exists "want_likes readable with the want" on public.want_likes;
create policy "want_likes readable with the want"
  on public.want_likes for select
  using (exists (select 1 from public.wants w where w.id = want_id));

drop policy if exists "want_likes are your own to write" on public.want_likes;
create policy "want_likes are your own to write"
  on public.want_likes for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "want_comments readable with the want" on public.want_comments;
create policy "want_comments readable with the want"
  on public.want_comments for select
  using (exists (select 1 from public.wants w where w.id = want_id));

drop policy if exists "want_comments are your own to write" on public.want_comments;
create policy "want_comments are your own to write"
  on public.want_comments for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
