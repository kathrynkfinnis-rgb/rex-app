-- Oct 16, security review — F21, and F24 while the file is open.
--
-- Ask Rex caps a person at forty questions a rolling day (29 Sept). The three
-- other functions that call a paid model cap nothing at all:
--
--   extract-recommendations  claude-sonnet-5, max_tokens 8192, input sliced at
--                            200,000 characters — roughly 50k tokens a call
--   organise-list            claude-sonnet-5, max_tokens 4096, 400 lines, and
--                            no limit on the length of a line
--   extract-recipe-photo     claude-haiku-4-5, an image with no size cap at all
--
-- So one account in a loop, or one retry bug in the app, runs up an Anthropic
-- bill overnight with nothing in the way. `organise-list` is the sharpest:
-- MAX_LINES bounds the array and nothing bounds each string, so four hundred
-- hundred-kilobyte lines is a single enormous request.
--
-- This is the `rex_asks` shape generalised — one table, a `kind` column, and
-- deliberately no DELETE policy so nobody can reset their own limit by
-- emptying it. The per-request byte caps go in the functions themselves,
-- where the request body actually is.

create table if not exists public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  used_at timestamptz not null default now()
);

create index if not exists ai_usage_user_kind_time_idx
  on public.ai_usage (user_id, kind, used_at desc);

grant select, insert on public.ai_usage to authenticated;
grant all on public.ai_usage to service_role;

alter table public.ai_usage enable row level security;

drop policy if exists "Users read own ai usage" on public.ai_usage;
create policy "Users read own ai usage" on public.ai_usage
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "Users log own ai usage" on public.ai_usage;
create policy "Users log own ai usage" on public.ai_usage
  for insert to authenticated with check (user_id = auth.uid());

-- No UPDATE and no DELETE policy, on purpose and for the same reason rex_asks
-- has none: a limit you can clear by emptying the table is not a limit.

comment on table public.ai_usage is
  'One row per call to a paid AI feature, per person. Append-only by policy so nobody can reset their own ceiling. See the per-kind limits in the edge functions.';

-- ─────────────────────────────────────────────────────────────────────
-- F24 — the prune that was written and never scheduled.
--
-- prune_rex_asks has existed since 29 September and nothing has ever called
-- it: grepping the repo returns its own definition and the REVOKE beside it.
-- So rex_asks has grown since the day it was created, and ai_usage above
-- would do the same.
--
-- Both are rate-limit bookkeeping with no value past their window. Thirty
-- days is well beyond the rolling day the limits actually read.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.prune_ai_usage()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.ai_usage where used_at < now() - interval '30 days';
  delete from public.rex_asks where asked_at < now() - interval '30 days';
$$;

revoke all on function public.prune_ai_usage() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Unschedule first so re-running this migration doesn't double it up.
    -- A nested block, because cron.unschedule raises when the job isn't
    -- there and that is the normal case the first time.
    begin
      perform cron.unschedule('prune-ai-usage');
    exception when others then
      null;
    end;

    perform cron.schedule('prune-ai-usage', '17 4 * * *',
      $cron$select public.prune_ai_usage();$cron$);
  else
    raise notice 'pg_cron not installed — prune_ai_usage() exists but nothing will call it.';
  end if;
end $$;
