-- Oct 12 — "Phoebe uploaded this as Rex but the items come up under her
-- account."
--
-- The code fix landed this morning: a list posted as REX now writes its items
-- under the official account rather than under whoever was signed in. That only
-- governs what is written from now on. Everything already uploaded still says
-- REX on the collection and Phoebe on all fifteen things inside it, which is
-- exactly what she is looking at.
--
-- A list is itself a recommendation, and its items are recommendations whose
-- list_id points at it; trip stops work the same way through trip_id. So the
-- rule is simple and local: if the parent belongs to the official account, the
-- children do too. Nothing else is touched — a list of Phoebe's stays entirely
-- Phoebe's, and an item whose parent is already correct is already excluded by
-- the user_id check.
--
-- Deliberately one-directional. There is no case where a child of a REX list
-- should sit under a person, but there are plenty where someone's own list
-- legitimately contains items under their name, so this never runs the other
-- way.
--
-- Safe to run twice: the second run matches nothing.
do $$
declare
  official uuid := public.official_account_id();
  moved_items integer;
  moved_stops integer;
begin
  if official is null then
    raise notice 'No official account on this database — nothing to do.';
    return;
  end if;

  with parents as (
    select id from public.recommendations where user_id = official
  )
  update public.recommendations child
     set user_id = official
   where child.list_id in (select id from parents)
     and child.user_id is distinct from official;
  get diagnostics moved_items = row_count;

  with parents as (
    select id from public.recommendations where user_id = official
  )
  update public.recommendations child
     set user_id = official
   where child.trip_id in (select id from parents)
     and child.user_id is distinct from official;
  get diagnostics moved_stops = row_count;

  raise notice 'Moved % list items and % trip stops to the official account.',
    moved_items, moved_stops;
end $$;
