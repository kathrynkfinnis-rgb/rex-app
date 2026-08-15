-- Drafts (#66): let a Rex or trip be saved without publishing, e.g.
-- journaling trip stops one at a time and publishing the whole itinerary at
-- the end.
--
-- published_at nullable, NULL = draft. Backfilled to created_at for every
-- existing row so nothing already live silently becomes a draft.
ALTER TABLE public.recommendations ADD COLUMN IF NOT EXISTS published_at timestamptz;
UPDATE public.recommendations SET published_at = created_at WHERE published_at IS NULL;
ALTER TABLE public.recommendations ALTER COLUMN published_at SET DEFAULT now();

-- Enforcement lives in RLS rather than being left to every client query to
-- remember: you can always see your own rows (draft or not), but a friend
-- only ever sees published ones. This is the only thing that actually
-- guarantees a draft can't leak through some fetch path that forgot to
-- filter published_at itself - feed, item pages, map, leaderboard, search,
-- all of it, automatically.
ALTER POLICY "See own and friends' recommendations"
  ON public.recommendations
  USING (
    auth.uid() = user_id
    OR (published_at IS NOT NULL AND public.are_friends(auth.uid(), user_id))
  );

CREATE INDEX IF NOT EXISTS recommendations_published_idx ON public.recommendations(user_id, published_at);
