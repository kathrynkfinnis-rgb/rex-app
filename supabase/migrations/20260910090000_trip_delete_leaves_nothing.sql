-- Sept 10 — "if someone has saved a trip to 'want to try' but the trip has
-- been deleted, it should disappear from the want to try list as well.
-- Basically there should be no remnants anywhere of the trip."
--
-- A trip is three kinds of row, and deleting one only ever removed the
-- first:
--
--   1. the trip's own recommendation — what "delete" actually deleted
--   2. its stops, each a recommendation pointing at it through trip_id
--   3. the trip's own catalogue item (items.type = 'trip'), which is what
--      a want points at — "Gemma wants to try Loire Valley" is a row in
--      `wants` against that item, not against the recommendation
--
-- (2) had ON DELETE SET NULL, so deleting a trip quietly turned every one
-- of its stops into a free-standing Rex. The app has deleted them itself
-- since 8 Sept, but only the app — anything else deleting a trip still
-- orphaned them. (3) was never touched, so a deleted trip lived on in
-- everyone's want-to-try list, pointing at nothing.
--
-- Lists have the same shape and the same problem at (3); list_id already
-- cascades, so they only need the item cleanup.

-- (2) — stops go with their trip, the same way list items already go with
-- their list.
alter table public.recommendations
  drop constraint if exists recommendations_trip_id_fkey;
alter table public.recommendations
  add constraint recommendations_trip_id_fkey
  foreign key (trip_id) references public.recommendations(id) on delete cascade;

-- (3) — once the last recommendation of a trip or list item is gone, the
-- item goes too, and wants.item_id's own ON DELETE CASCADE takes every
-- want-to-try with it.
--
-- Security definer because the wants being removed are other people's:
-- you can delete your own trip, and RLS rightly won't let you touch
-- Gemma's rows directly, but her want of a trip that no longer exists is
-- not hers to keep.
--
-- Only trip and list items. A place, book or film item is shared
-- catalogue — deleting your Rex of The Ivy must never delete The Ivy for
-- everyone else who has it saved.
create or replace function public.delete_orphaned_container_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.items i
    where i.id = old.item_id and i.type in ('trip', 'list')
  ) and not exists (
    select 1 from public.recommendations r where r.item_id = old.item_id
  ) then
    begin
      delete from public.items where id = old.item_id;
    exception when foreign_key_violation then
      -- Something outside the trip still points at the item (an editorial
      -- collection entry, say). Leave the item; its wants can still go.
      delete from public.wants where item_id = old.item_id;
    end;
  end if;
  return old;
end;
$$;

drop trigger if exists recommendations_delete_orphaned_container_item on public.recommendations;
create trigger recommendations_delete_orphaned_container_item
  after delete on public.recommendations
  for each row execute function public.delete_orphaned_container_item();

-- And the remnants already out there: trip and list items whose trip or
-- list has already been deleted. Wants on them go with them.
delete from public.wants w
using public.items i
where w.item_id = i.id
  and i.type in ('trip', 'list')
  and not exists (select 1 from public.recommendations r where r.item_id = i.id);

delete from public.items i
where i.type in ('trip', 'list')
  and not exists (select 1 from public.recommendations r where r.item_id = i.id)
  -- The one reference without a cascade; an editorial pick keeps its item.
  and not exists (select 1 from public.editorial_collection_items e where e.item_id = i.id);
