-- Oct 15 — "why are these two separate pins when they are the same
-- restaurant?" Le Relais de Venise, twice, at 120 Marylebone Lane: once as
-- "Le Relais de Venise L'Entrecote | Marylebone" and once as "Le Relais de
-- Venise l'Entrecôte".
--
-- The app stopped making new pairs on 15 October (normalizeForMatch folded no
-- accents, so "l'Entrecôte" became "lentrec te" — a word with a hole in it —
-- and could never match "lentrecote"). This is the repair for the ones
-- already in the catalogue.
--
-- The oyster bar merge on 4 October did this for one known pair by id. That
-- was the honest shape then, because the two rows shared nothing a rule could
-- match on. These share an address exactly, so a rule can find them, and
-- finding them is better than me being told about each one.

-- 1. The merge itself, lifted out of the oyster bar migration so it stops
--    being a thing that gets rewritten by hand each time.
--
--    Repointing a recommendation onto an item the same person has already
--    Rex'd would violate recommendations_unique_standalone, so those are
--    dropped rather than moved: it is the same person saying the same thing
--    about the same place twice. Same reasoning for wants and suggestions.
create or replace function public.merge_items(loser uuid, keeper uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if loser = keeper then return; end if;

  delete from public.recommendations r
  where r.item_id = loser
    and exists (
      select 1 from public.recommendations k
      where k.item_id = keeper
        and k.user_id = r.user_id
        and k.trip_id is not distinct from r.trip_id
        and k.list_id is not distinct from r.list_id
    );
  update public.recommendations set item_id = keeper where item_id = loser;

  delete from public.wants w
  where w.item_id = loser
    and exists (select 1 from public.wants k where k.item_id = keeper and k.user_id = w.user_id);
  update public.wants set item_id = keeper where item_id = loser;

  delete from public.rex_suggestions s
  where s.item_id = loser
    and exists (select 1 from public.rex_suggestions k where k.item_id = keeper and k.user_id = s.user_id);
  update public.rex_suggestions set item_id = keeper where item_id = loser;

  update public.editorial_collection_items set item_id = keeper where item_id = loser;
  update public.check_ins set item_id = keeper where item_id = loser;
  update public.request_comments set suggested_item_id = keeper where suggested_item_id = loser;
  update public.import_staging set resolved_item_id = keeper where resolved_item_id = loser;

  delete from public.items where id = loser;
end;
$$;

comment on function public.merge_items is
  'Folds one item into another: everything pointing at the loser is repointed at the keeper, except rows that would collide with one the same person already has, which are dropped. The loser is deleted.';

-- 2. Normalising a name the way the app does, so the two agree about what
--    counts as the same place.
--
--    translate() rather than unaccent(), which is an extension this database
--    may not have — the characters below are the ones that actually turn up in
--    restaurant names here.
create or replace function public.rex_normalise_name(raw text)
returns text
language sql
immutable
as $$
  select nullif(
    trim(regexp_replace(
      translate(
        lower(split_part(coalesce(raw, ''), '|', 1)),
        'àáâãäåèéêëìíîïòóôõöùúûüýÿñçœæ',
        'aaaaaaeeeeiiiiooooouuuuyyncoa'
      ),
      '[^a-z0-9]+', ' ', 'g'
    )),
  '');
$$;

-- 3. Merge the pairs. Deliberately narrow: an identical address, a matching
--    normalised name, and the same type. An address match on its own would
--    fold the three restaurants in a food hall into one.
--
--    The keeper is the row best able to draw a pin and carry a card — a Google
--    id, then coordinates, then an image, then whichever is older.
do $$
declare
  grp record;
  keeper uuid;
  other uuid;
begin
  for grp in
    select
      type,
      lower(trim(address)) as addr,
      public.rex_normalise_name(title) as name,
      array_agg(id order by
        (external_id is not null) desc,
        (lat is not null and lng is not null) desc,
        (image_url is not null) desc,
        created_at asc
      ) as ids
    from public.items
    where address is not null
      and trim(address) <> ''
      and public.rex_normalise_name(title) is not null
    group by 1, 2, 3
    having count(*) > 1
  loop
    keeper := grp.ids[1];
    foreach other in array grp.ids[2:array_length(grp.ids, 1)] loop
      perform public.merge_items(other, keeper);
    end loop;
  end loop;
end $$;
