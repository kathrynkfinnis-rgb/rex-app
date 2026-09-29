-- Sept 29 — "Talk to Rex": the conversational half of Explore.
--
-- This migration adds only the memory. Everything else the feature needs to
-- read — your friends' Rex, their notes and ratings — already exists, and the
-- edge function reads it through PostgREST *as the signed-in user*, so the
-- existing row-level security is what decides whose Rex it can see. No
-- SECURITY DEFINER shortcut, no new way to read somebody else's
-- recommendations: if you can't see it in the feed, Talk to Rex can't see it
-- either.
--
-- On the memory itself. There are two ways to build this and they cost very
-- different amounts. Replaying every past conversation into every new one
-- grows without limit and punishes your heaviest users. Keeping a short list
-- of FACTS — "two kids, 6 and 9", "trusts Rotten Tomatoes", "won't start a
-- long film on a weeknight" — is a few hundred tokens a question and stays
-- flat however long someone uses REX. This is the second one.

-- ============================================================ facts
create table if not exists public.rex_facts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  -- One plain sentence, written by the model after a conversation and shown
  -- back to the user verbatim. Deliberately not structured: the moment this
  -- becomes a schema, someone has to decide in advance what a preference can
  -- be, and taste doesn't fit in columns.
  fact text not null check (length(btrim(fact)) between 3 and 300),
  -- What produced it, so the Settings screen can say "you told me this" vs
  -- "I noticed this", and so a bad inference can be traced.
  source text not null default 'inferred' check (source in ('inferred', 'stated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.rex_facts is
  'What Talk to Rex remembers about a user. Facts, not transcripts. Visible and deletable by the user in Settings.';

create index if not exists rex_facts_user_idx on public.rex_facts (user_id, updated_at desc);

-- The same fact twice is noise in the prompt and nonsense on the Settings
-- screen. Case-insensitive so "Two kids" doesn't join "two kids".
create unique index if not exists rex_facts_user_fact_idx
  on public.rex_facts (user_id, lower(btrim(fact)));

alter table public.rex_facts enable row level security;

-- Yours and nobody else's — not even friends. What REX has worked out about
-- you is more revealing than anything you've posted, and none of it was
-- deliberately shared.
drop policy if exists "Users read own facts" on public.rex_facts;
create policy "Users read own facts" on public.rex_facts
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "Users write own facts" on public.rex_facts;
create policy "Users write own facts" on public.rex_facts
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "Users update own facts" on public.rex_facts;
create policy "Users update own facts" on public.rex_facts
  for update to authenticated using (auth.uid() = user_id);

drop policy if exists "Users delete own facts" on public.rex_facts;
create policy "Users delete own facts" on public.rex_facts
  for delete to authenticated using (auth.uid() = user_id);

grant select, insert, update, delete on public.rex_facts to authenticated;
grant all on public.rex_facts to service_role;

-- A ceiling, enforced where it can't be forgotten. Thirty facts is roughly
-- 350 tokens; without a cap the prompt grows quietly for years and the cost
-- model in the plan stops being true. Oldest-touched goes first.
create or replace function public.trim_rex_facts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.rex_facts
  where id in (
    select id from public.rex_facts
    where user_id = new.user_id
    order by updated_at desc
    offset 30
  );
  return null;
end;
$$;

drop trigger if exists rex_facts_trim on public.rex_facts;
create trigger rex_facts_trim
  after insert on public.rex_facts
  for each row execute function public.trim_rex_facts();

-- ============================================================ what it suggested
-- Kept apart from the facts, and far cheaper: ids only, never re-read into a
-- prompt as prose. Its one job is "don't suggest the same film three times".
create table if not exists public.rex_suggestions (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  suggested_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

comment on table public.rex_suggestions is
  'Items Talk to Rex has already put in front of this user, so it can avoid repeating itself.';

create index if not exists rex_suggestions_user_idx
  on public.rex_suggestions (user_id, suggested_at desc);

alter table public.rex_suggestions enable row level security;

drop policy if exists "Users read own suggestions" on public.rex_suggestions;
create policy "Users read own suggestions" on public.rex_suggestions
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "Users write own suggestions" on public.rex_suggestions;
create policy "Users write own suggestions" on public.rex_suggestions
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "Users delete own suggestions" on public.rex_suggestions;
create policy "Users delete own suggestions" on public.rex_suggestions
  for delete to authenticated using (auth.uid() = user_id);

grant select, insert, delete on public.rex_suggestions to authenticated;
grant all on public.rex_suggestions to service_role;
