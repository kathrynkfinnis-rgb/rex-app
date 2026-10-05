-- Oct 5 — "and can we truncate the link?"
--
-- A shared Rex currently reads
--   https://find-rex.com/r/1f701dd0-f501-400f-b6cd-08f94b1ab8cc
-- which is 59 characters, most of them a UUID nobody will ever read. In a
-- WhatsApp message sitting under a line of actual words it is the biggest
-- thing on screen. This makes it
--   https://find-rex.com/s/k3n9pqd
--
-- One table rather than a short_code column on each of recommendations,
-- wants and hitlist_lists: a code is not a property of the thing, it is a
-- pointer to it, and keeping them together means one place to look when a
-- link misbehaves and one resolver instead of three.
--
-- Codes are minted on demand, when somebody actually shares something —
-- not on insert. Minting for every Rex ever posted would fill this table
-- with codes for things nobody has sent to anyone.
create table if not exists public.share_links (
  code text primary key,
  kind text not null check (kind in ('rec', 'trip', 'want', 'list')),
  target_id uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (kind, target_id)
);

alter table public.share_links enable row level security;

-- No direct reads or writes: everything goes through the two functions
-- below, so a code can't be enumerated by listing the table.
revoke all on public.share_links from anon, authenticated;

comment on table public.share_links is
  'Short codes for shared links — find-rex.com/s/<code>. One row per thing ever shared, minted on demand by mint_share_code.';

-- The alphabet deliberately drops 0/O/1/l/I: these get read aloud and typed
-- by hand often enough that confusable characters cost more than the two
-- bits they save. 31^7 is about 27 billion, so collisions stay theoretical,
-- and the loop below handles one anyway.
CREATE OR REPLACE FUNCTION public.mint_share_code(_kind text, _id uuid)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  alphabet constant text := '23456789abcdefghjkmnpqrstuvwxyz';
  existing text;
  candidate text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'must be signed in to share';
  END IF;

  IF _kind NOT IN ('rec', 'trip', 'want', 'list') THEN
    RAISE EXCEPTION 'unknown share kind %', _kind;
  END IF;

  -- Sharing the same thing twice gives the same link, which matters: a link
  -- already sent to somebody keeps working, and two people sharing one Rex
  -- don't produce two different addresses for it.
  SELECT code INTO existing
  FROM public.share_links
  WHERE kind = _kind AND target_id = _id;
  IF existing IS NOT NULL THEN
    RETURN existing;
  END IF;

  -- Deliberately NOT checking that _id exists or that the caller can see it.
  -- A code on its own reveals nothing — resolve_share_code hands back an id,
  -- and the page behind it runs its own visibility checks exactly as it does
  -- for a full-length link today.
  FOR attempt IN 1..10 LOOP
    candidate := '';
    FOR i IN 1..7 LOOP
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    END LOOP;

    BEGIN
      INSERT INTO public.share_links (code, kind, target_id, created_by)
      VALUES (candidate, _kind, _id, auth.uid())
      RETURNING code INTO existing;
      RETURN existing;
    EXCEPTION WHEN unique_violation THEN
      -- Either the code collided (try again) or another session minted this
      -- same target a moment ago (take theirs).
      SELECT code INTO existing
      FROM public.share_links
      WHERE kind = _kind AND target_id = _id;
      IF existing IS NOT NULL THEN
        RETURN existing;
      END IF;
    END;
  END LOOP;

  RAISE EXCEPTION 'could not mint a share code';
END;
$$;

-- Open to anon: the whole point is that somebody without the app can follow
-- the link. It returns a kind and an id, nothing more — the page it leads to
-- decides what that person is allowed to see.
CREATE OR REPLACE FUNCTION public.resolve_share_code(_code text)
RETURNS TABLE (kind text, target_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.kind, s.target_id
  FROM public.share_links s
  WHERE s.code = lower(btrim(_code))
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.mint_share_code(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mint_share_code(text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.resolve_share_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_share_code(text) TO anon, authenticated;

COMMENT ON FUNCTION public.mint_share_code(text, uuid) IS
  'The short code for something, minting one the first time it is shared. Stable: sharing the same thing again returns the same code, so links already sent keep working.';
COMMENT ON FUNCTION public.resolve_share_code(text) IS
  'What a /s/<code> link points at. Returns a kind and an id only; the page behind it does its own visibility checks.';
