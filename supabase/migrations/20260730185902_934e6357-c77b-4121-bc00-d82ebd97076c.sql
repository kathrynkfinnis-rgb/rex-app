ALTER TABLE public.notification_preferences ADD COLUMN IF NOT EXISTS rec_saved boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.notif_pref_enabled(_user uuid, _type text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v boolean;
BEGIN
  SELECT
    CASE _type
      WHEN 'rec_like' THEN rec_like
      WHEN 'rec_comment' THEN rec_comment
      WHEN 'rec_saved' THEN rec_saved
      WHEN 'friend_request' THEN friend_request
      WHEN 'friend_accepted' THEN friend_accepted
      WHEN 'blast_new' THEN blast_new
      WHEN 'blast_comment' THEN blast_comment
      WHEN 'friend_new_rec' THEN friend_new_rec
      ELSE true
    END
  INTO v
  FROM public.notification_preferences
  WHERE user_id = _user;

  IF v IS NULL THEN
    RETURN _type <> 'friend_new_rec';
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.tg_notify_rec_saved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  owner_id uuid;
BEGIN
  SELECT user_id INTO owner_id FROM public.recommendations WHERE id = NEW.recommendation_id;
  IF owner_id IS NULL OR owner_id = NEW.user_id THEN RETURN NEW; END IF;
  IF NOT public.notif_pref_enabled(owner_id, 'rec_saved') THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id)
  VALUES (owner_id, NEW.user_id, 'rec_saved', 'recommendation', NEW.recommendation_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_rec_saved ON public.saved_posts;
CREATE TRIGGER trg_notify_rec_saved
AFTER INSERT ON public.saved_posts
FOR EACH ROW EXECUTE FUNCTION public.tg_notify_rec_saved();

REVOKE ALL ON FUNCTION public.tg_notify_rec_saved() FROM PUBLIC, anon, authenticated;