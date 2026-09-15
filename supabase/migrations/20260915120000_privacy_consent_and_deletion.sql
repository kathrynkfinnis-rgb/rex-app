-- Sept 15 — privacy features: consent logged with a timestamp and version,
-- and self-service account deletion (GDPR right to erasure; also an App
-- Store requirement for any app that lets you create an account).

-- ============================================================ consent
-- Sign-up already stamped profiles.accepted_terms_at, but each acceptance
-- overwrote the last, nothing said WHICH version of the Terms and Privacy
-- Policy was agreed to, and accounts from before 27 Aug have no record at
-- all. A proper log: one row per acceptance, never updated.
create table if not exists public.consent_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  -- 'terms_privacy' for now; a separate document (marketing consent, say)
  -- would get its own name rather than a new table.
  document text not null default 'terms_privacy',
  version text not null,
  accepted_at timestamptz not null default now(),
  -- 'signup' | 'update' — accepted when joining, or when a new version was
  -- put in front of an existing account.
  source text not null,
  app_version text
);

create index if not exists consent_log_user_idx on public.consent_log (user_id, accepted_at desc);

alter table public.consent_log enable row level security;

drop policy if exists "consent_log own insert" on public.consent_log;
create policy "consent_log own insert" on public.consent_log
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "consent_log own read" on public.consent_log;
create policy "consent_log own read" on public.consent_log
  for select to authenticated using (user_id = auth.uid());

-- No update or delete policy on purpose: a consent record that can be
-- edited afterwards isn't a record.
grant select, insert on public.consent_log to authenticated;
grant all on public.consent_log to service_role;

-- The latest version each account has agreed to, so the app can tell at a
-- glance whether to ask again after the policy changes.
alter table public.profiles
  add column if not exists accepted_terms_version text;

-- ============================================================ deletion
-- "Delete my account and data." Called by the signed-in person, for
-- themselves only — it reads auth.uid(), never an argument.
--
-- Deleting the auth user cascades through everything that references it
-- (profile, Rex, wants, comments, likes, friendships, collections, blasts,
-- push tokens, consent log...), and the 10 Sept trigger removes any trip
-- or list items left without a Rex. A handful of tables were never given
-- a foreign key to auth.users, so those are cleared by hand first.
--
-- Photos in Storage (avatars and rec-photos) are deleted by the app
-- through the Storage API before this runs — Supabase doesn't allow
-- removing Storage files from SQL, and deleting only the metadata would
-- leave the image files behind.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  -- Tables with a user column but no cascade from auth.users.
  delete from public.saved_posts where user_id = me;
  delete from public.notifications where user_id = me or actor_id = me;
  delete from public.notification_preferences where user_id = me;
  delete from public.import_staging where user_id = me;
  delete from public.list_collaborators where user_id = me;
  delete from public.group_shares where user_id = me;
  delete from public.group_members where user_id = me;
  delete from public.groups where owner_id = me;
  -- An editorial collection someone curated outlives them, unattributed.
  update public.editorial_collections set created_by = null where created_by = me;

  delete from auth.users where id = me;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
