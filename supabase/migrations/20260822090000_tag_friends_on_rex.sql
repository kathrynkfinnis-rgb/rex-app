-- #162: tag friend(s) on a Rex ("went here with Phoebe"). A join table
-- (not a uuid[] column on recommendations) so PostgREST can embed the
-- tagged profiles directly on a card fetch the same way recommendations
-- already embeds profiles/creators elsewhere in this app, rather than a
-- separate round-trip per card.
CREATE TABLE public.recommendation_tags (
  recommendation_id uuid NOT NULL REFERENCES public.recommendations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (recommendation_id, user_id)
);
CREATE INDEX recommendation_tags_user_idx ON public.recommendation_tags(user_id);

GRANT SELECT, INSERT, DELETE ON public.recommendation_tags TO authenticated;
GRANT ALL ON public.recommendation_tags TO service_role;

ALTER TABLE public.recommendation_tags ENABLE ROW LEVEL SECURITY;

-- Same visibility as the recommendation itself (feed/profile cards are
-- broadly readable already) — tags aren't a secret, they're shown on the card.
CREATE POLICY "Tags are visible to anyone" ON public.recommendation_tags
  FOR SELECT TO authenticated USING (true);

-- Only the Rex's own author can tag or untag people on it.
CREATE POLICY "Author tags people on own Rex" ON public.recommendation_tags
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.recommendations r
      WHERE r.id = recommendation_id AND r.user_id = auth.uid()
    )
  );
CREATE POLICY "Author untags people from own Rex" ON public.recommendation_tags
  FOR DELETE TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.recommendations r
      WHERE r.id = recommendation_id AND r.user_id = auth.uid()
    )
  );

-- Notification preference + trigger, matching the existing rec_like/
-- rec_comment/friend_new_rec pattern in notification_preferences.
ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS rec_tagged boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.notif_pref_enabled(_user uuid, _type text)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v boolean;
BEGIN
  SELECT
    CASE _type
      WHEN 'rec_like' THEN rec_like
      WHEN 'rec_comment' THEN rec_comment
      WHEN 'friend_request' THEN friend_request
      WHEN 'friend_accepted' THEN friend_accepted
      WHEN 'blast_new' THEN blast_new
      WHEN 'blast_comment' THEN blast_comment
      WHEN 'friend_new_rec' THEN friend_new_rec
      WHEN 'rec_tagged' THEN rec_tagged
      ELSE true
    END
  INTO v
  FROM public.notification_preferences
  WHERE user_id = _user;

  IF v IS NULL THEN
    -- default when no prefs row: friend_new_rec off, everything else on
    RETURN _type <> 'friend_new_rec';
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.tg_notify_rec_tagged()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE actor uuid;
BEGIN
  SELECT user_id INTO actor FROM public.recommendations WHERE id = NEW.recommendation_id;
  IF actor IS NULL OR actor = NEW.user_id THEN RETURN NEW; END IF;
  IF NOT public.notif_pref_enabled(NEW.user_id, 'rec_tagged') THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id)
  VALUES (NEW.user_id, actor, 'rec_tagged', 'recommendation', NEW.recommendation_id);
  RETURN NEW;
END;
$$;
CREATE TRIGGER notify_rec_tagged AFTER INSERT ON public.recommendation_tags
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_rec_tagged();
