-- Explore tab: editorial shelves ("REX team" picks + "from around the web",
-- distinguished by source_label rather than two separate tables since both
-- are just a human typing in a few items with attribution) and a trending
-- -items RPC, same SECURITY DEFINER pattern as top_rexxers_weekly.

CREATE TABLE public.editorial_collections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  -- "REX Team" by default; someone curating can override it to credit an
  -- external source instead, e.g. "via Conde Nast Traveller" - it's still a
  -- REX person typing the row in, just crediting where the idea came from.
  source_label text NOT NULL DEFAULT 'REX Team',
  -- One of RexCategory's raw values (place/trip/book/...), or null to show
  -- under every filter rather than a specific one.
  category text,
  sort_order integer NOT NULL DEFAULT 0,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.editorial_collection_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  collection_id uuid NOT NULL REFERENCES public.editorial_collections(id) ON DELETE CASCADE,
  title text NOT NULL,
  subtitle text,
  image_url text,
  -- Optional: point at a real catalogue item so tapping opens the normal
  -- item page. Left null for something that isn't in the REX catalogue at
  -- all yet (e.g. a web article rather than a book/place/etc).
  item_id uuid REFERENCES public.items(id),
  -- Optional external link, for "from around the web" items with nothing
  -- to link to in-app.
  link_url text,
  sort_order integer NOT NULL DEFAULT 0
);

ALTER TABLE public.editorial_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.editorial_collection_items ENABLE ROW LEVEL SECURITY;

-- Everyone signed in can read the shelves.
CREATE POLICY "Editorial collections are viewable by authenticated users"
  ON public.editorial_collections FOR SELECT TO authenticated USING (true);
CREATE POLICY "Editorial collection items are viewable by authenticated users"
  ON public.editorial_collection_items FOR SELECT TO authenticated USING (true);

-- Only the named curators can write. By username rather than a hardcoded
-- id list, since usernames are what's actually known/verifiable here and
-- rarely change - swap this predicate if the curator list changes rather
-- than looking up and pasting in raw uuids.
CREATE OR REPLACE FUNCTION public.is_rex_curator()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND username IN ('kathrynkfinnis', 'phoebebragg', 'gemmahitchens')
  )
$$;
REVOKE ALL ON FUNCTION public.is_rex_curator() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_rex_curator() TO authenticated;

CREATE POLICY "Curators manage editorial collections"
  ON public.editorial_collections FOR ALL TO authenticated
  USING (public.is_rex_curator()) WITH CHECK (public.is_rex_curator());
CREATE POLICY "Curators manage editorial collection items"
  ON public.editorial_collection_items FOR ALL TO authenticated
  USING (public.is_rex_curator()) WITH CHECK (public.is_rex_curator());

GRANT SELECT ON public.editorial_collections TO authenticated;
GRANT SELECT ON public.editorial_collection_items TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.editorial_collections TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.editorial_collection_items TO authenticated;

-- Trending shelf: most-Rex'd items in the last 7 days. Excludes trip stops
-- (a trip's individual stops aren't meant to compete here, same exclusion
-- fetchRexCounts already makes) and unpublished drafts (SECURITY DEFINER
-- bypasses RLS, so published_at has to be checked explicitly here or a
-- draft could leak into everyone's Explore tab).
CREATE OR REPLACE FUNCTION public.trending_items_weekly(_limit integer DEFAULT 10)
RETURNS TABLE(item_id uuid, title text, subtitle text, image_url text, type text, rex_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT i.id, i.title, i.subtitle, i.image_url, i.type, count(r.id) AS rex_count
  FROM public.recommendations r
  JOIN public.items i ON i.id = r.item_id
  WHERE r.created_at >= now() - interval '7 days'
    AND r.trip_id IS NULL
    AND r.published_at IS NOT NULL
  GROUP BY i.id, i.title, i.subtitle, i.image_url, i.type
  ORDER BY rex_count DESC, i.title ASC
  LIMIT greatest(1, least(coalesce(_limit, 10), 30))
$$;

REVOKE ALL ON FUNCTION public.trending_items_weekly(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.trending_items_weekly(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.trending_items_weekly(integer) TO service_role;
