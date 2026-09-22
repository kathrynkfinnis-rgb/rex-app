-- Sept 22 — Sign in with Apple token revocation, which Apple requires of any
-- app that offers both Sign in with Apple and account deletion. REX offers
-- both, so without this the submission is a guideline 5.1.1 rejection.
--
-- The shape of it: when someone signs in with Apple, the app also hands us
-- Apple's one-time authorization code. A server function exchanges that with
-- Apple for a refresh token and parks it here. When the same person deletes
-- their account, that refresh token is what lets us tell Apple to forget the
-- connection between them and REX — which is the whole point: deleting your
-- account shouldn't leave REX listed under your Apple ID for ever.

create table if not exists public.apple_credentials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- Apple's refresh token. Never leaves the server: no policy grants any
  -- authenticated role access to this table, so only the service role — which
  -- is to say, the edge function — can read or write it.
  refresh_token text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.apple_credentials enable row level security;

-- Deliberately no policies at all. RLS with no policy means every request
-- from an ordinary signed-in user sees nothing and writes nothing, which is
-- exactly right for a table of other people's credentials.
revoke all on public.apple_credentials from anon, authenticated;
grant all on public.apple_credentials to service_role;

comment on table public.apple_credentials is
  'Apple refresh tokens, used only to revoke the Sign in with Apple connection when an account is deleted. Service role only.';
