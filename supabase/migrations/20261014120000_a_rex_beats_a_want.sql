-- Oct 14 — "you shouldn't be able to have a Rex and a want to try for the same
-- thing (still happening). The Rex should always win."
--
-- The app already tidied the want away when you posted a Rex (14 Oct,
-- clearWantOnReview), and that part works. It was never enough, for two
-- reasons:
--
--   1. Every pair that existed before that shipped is still there. Nothing has
--      ever gone back and settled them, and they are what she is looking at.
--   2. It only closed one direction. Nothing stopped you adding a want for
--      something you had already Rex'd — bookmarking a friend's Rex of a place
--      you'd reviewed yourself did exactly that, silently.
--
-- "Should always win" is an invariant, and an invariant enforced only by the
-- client is a convention. This settles the existing pairs and then makes the
-- rule true in the database, from either direction.

-- 1. Carry collection placements across before deleting anything.
--
-- A want sitting in a collection is a row *in* that collection. Deleting it
-- without moving its placement would quietly take the thing off the list it
-- was on — which is the bug clearWantOnReview was written to avoid, and the
-- same care is owed to the rows being settled here. Where the Rex is already
-- in that collection we leave it alone rather than adding a second entry.
insert into public.saved_posts (list_id, recommendation_id, section, sort_order, note)
select w.list_id, r.id, w.list_section, w.list_sort_order, w.list_note
from public.wants w
join public.recommendations r
  on r.user_id = w.user_id
 and r.item_id = w.item_id
 and r.published_at is not null
 and coalesce(r.is_branch_copy, false) = false
where w.list_id is not null
  and not exists (
    select 1 from public.saved_posts s
    where s.list_id = w.list_id and s.recommendation_id = r.id
  );

-- 2. Settle the existing pairs. The Rex stays, the want goes.
-- Same three exclusions as the trigger: a draft, a scheduled post and a
-- branch copy are not Rexes, and a want underneath one is still a want.
delete from public.wants w
where exists (
  select 1 from public.recommendations r
  where r.user_id = w.user_id
    and r.item_id = w.item_id
    and r.published_at is not null
    and coalesce(r.is_branch_copy, false) = false
);

-- 3. Keep it true, in both directions.
--
-- A trigger rather than a constraint: the rule spans two tables, so there is
-- no single row a check could look at, and an exclusion constraint can't cross
-- tables either.
create or replace function public.rex_beats_want()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_table_name = 'wants' then
    -- Adding a want for something you have already Rex'd. Not an error: you
    -- asked for the thing to be on your list and it already is, as a Rex.
    -- Swallowing the insert is the honest answer to "the Rex should win".
    if exists (
      select 1 from public.recommendations r
      where r.user_id = new.user_id and r.item_id = new.item_id
    ) then
      return null;
    end if;
  else
    -- Posting a Rex for something you wanted. The want's placement has
    -- already been carried over by the app where there was one; this is the
    -- backstop for every path that doesn't go through it — a scheduled post
    -- landing, an import, a draft being published.
    --
    -- Three kinds of row are not a Rex yet and must not clear anything:
    -- a draft and a scheduled post have not been said, and a branch copy is
    -- somewhere you have not been. published_at is null for the first two
    -- (see createRecommendation), which is also why the clear has to happen
    -- on UPDATE as well — publishing a draft sets published_at, and that is
    -- the moment it becomes a Rex.
    if new.published_at is not null and coalesce(new.is_branch_copy, false) = false then
      delete from public.wants w
      where w.user_id = new.user_id and w.item_id = new.item_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists wants_yield_to_rex on public.wants;
create trigger wants_yield_to_rex
  before insert on public.wants
  for each row execute function public.rex_beats_want();

drop trigger if exists rex_clears_want on public.recommendations;
create trigger rex_clears_want
  after insert or update of published_at on public.recommendations
  for each row execute function public.rex_beats_want();

comment on function public.rex_beats_want is
  'A person cannot hold a Rex and a want for the same item. The Rex wins: a want inserted over one is dropped, and a new Rex clears any want underneath it.';
