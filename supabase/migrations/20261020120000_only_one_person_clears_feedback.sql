-- Oct 19 — "On the feedback page we should have the ability to X a feedback
-- if we've dealt with it — only Kathryn should have that ability."
--
-- Two things this does not need. It does not need a column: `status` has
-- been on public.feedback since 30 July with a default of 'new', and nothing
-- has ever written to it. And it does not need a role: admin is the wrong
-- test, because Gemma was made an admin on 19 October so she could see the
-- queue, and three people ticking items off one shared list is how two of
-- them lose track of what has been read.
--
-- So: one flag naming one person, and an update policy that asks the
-- database the same question the app asks before drawing the button. The
-- app's check decides whether the X appears; this decides whether it works,
-- which is the half that matters. Nothing here is a secret — who runs REX is
-- not sensitive — so the flag sits on the profile in plain sight.

alter table public.profiles
  add column if not exists is_owner boolean not null default false;

comment on column public.profiles.is_owner is
  'The one person who can clear feedback. Not a permission system — a single named exception, deliberately narrower than admin.';

-- At most one. Two owners is the thing this column exists to prevent, and a
-- partial unique index says so in the schema rather than in a comment.
create unique index if not exists profiles_single_owner_idx
  on public.profiles ((is_owner)) where is_owner;

-- The feedback table has had GRANT UPDATE to authenticated since 30 July and
-- no update policy to go with it, so every update has been refused by RLS.
-- This is the first one.
drop policy if exists "owner clears feedback" on public.feedback;
create policy "owner clears feedback" on public.feedback
  for update to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_owner)
  )
  with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_owner)
  );
