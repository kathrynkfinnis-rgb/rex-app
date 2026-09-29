-- Sept 29 — a ceiling on Talk to Rex, per person.
--
-- The cost model assumes about eight questions a month each. Nothing enforced
-- that. One person in a loop — or one bug in the app that retries — could run
-- up a Gemini bill overnight with no cap anywhere between them and Google,
-- and the first anyone would know is the invoice.
--
-- Forty in a rolling day is far above any honest use of the feature (the model
-- assumes eight a *month*) and far below anything that costs real money: forty
-- questions is about 24p. It is a runaway guard, not a product limit, and
-- nobody using REX normally will ever see it.

create table if not exists public.rex_asks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  asked_at timestamptz not null default now()
);

comment on table public.rex_asks is
  'One row per answered Talk to Rex question, for rate limiting. Doubles as the usage figure for the KPI dashboard.';

-- The only query this table serves: "how many in the last day for this user".
create index if not exists rex_asks_user_time_idx
  on public.rex_asks (user_id, asked_at desc);

alter table public.rex_asks enable row level security;

-- Readable by its owner so the app could show "you've asked a lot today"
-- rather than a bare refusal. Not writable in a way that could be used to
-- clear the count: no delete policy at all, so nobody can reset their own
-- limit by emptying the table.
drop policy if exists "Users read own asks" on public.rex_asks;
create policy "Users read own asks" on public.rex_asks
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "Users log own asks" on public.rex_asks;
create policy "Users log own asks" on public.rex_asks
  for insert to authenticated with check (auth.uid() = user_id);

grant select, insert on public.rex_asks to authenticated;
grant all on public.rex_asks to service_role;

-- Old rows are dead weight — the window is 24 hours and nothing reads further
-- back. Kept for 30 days so the dashboard has something to count, then gone.
create or replace function public.prune_rex_asks()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.rex_asks where asked_at < now() - interval '30 days';
$$;

revoke all on function public.prune_rex_asks() from public, anon, authenticated;
