-- Sept 17 — push notifications have never worked, and this is why.
--
-- Build 44's diagnostics reported: "token save failed: You don't have
-- permission to do that." Apple hands the phone its push address fine; the
-- insert into push_tokens is refused. So the grants and policies from the
-- 26 Aug push migration aren't in place in production — the table exists,
-- but authenticated users can't write to it.
--
-- Re-applied idempotently. Nothing here is destructive.

grant select, insert, delete on public.push_tokens to authenticated;
grant all on public.push_tokens to service_role;

alter table public.push_tokens enable row level security;

drop policy if exists "Users manage own push tokens" on public.push_tokens;
create policy "Users manage own push tokens" on public.push_tokens
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "Users remove own push tokens" on public.push_tokens;
create policy "Users remove own push tokens" on public.push_tokens
  for delete to authenticated using (auth.uid() = user_id);

-- Reading your own back matters for the app to tell you this phone is
-- registered, and for PostgREST to answer an upsert without erroring.
drop policy if exists "Users read own push tokens" on public.push_tokens;
create policy "Users read own push tokens" on public.push_tokens
  for select to authenticated using (auth.uid() = user_id);
