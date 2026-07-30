ALTER TABLE public.notification_preferences ADD COLUMN IF NOT EXISTS mention boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.notif_pref_enabled(_user uuid, _type text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      WHEN 'mention' THEN mention
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
$function$;

CREATE OR REPLACE FUNCTION public.tg_notify_rec_mention()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE names text[];
BEGIN
  SELECT array_agg(DISTINCT lower(m[1]))
    INTO names
  FROM regexp_matches(coalesce(NEW.body, ''), '@([A-Za-z0-9_]{2,30})', 'g') AS m;

  IF names IS NULL THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
  SELECT p.id, NEW.user_id, 'mention', 'recommendation', NEW.recommendation_id,
         jsonb_build_object('preview', left(NEW.body, 140))
  FROM public.profiles p
  WHERE lower(p.username) = ANY(names)
    AND p.id <> NEW.user_id
    AND public.notif_pref_enabled(p.id, 'mention');

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.tg_notify_blast_mention()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE names text[]; owner_title text;
BEGIN
  SELECT array_agg(DISTINCT lower(m[1]))
    INTO names
  FROM regexp_matches(coalesce(NEW.body, ''), '@([A-Za-z0-9_]{2,30})', 'g') AS m;

  IF names IS NULL THEN RETURN NEW; END IF;

  SELECT title INTO owner_title FROM public.requests WHERE id = NEW.request_id;

  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
  SELECT p.id, NEW.user_id, 'mention', 'request', NEW.request_id,
         jsonb_build_object('preview', left(NEW.body, 140), 'title', owner_title)
  FROM public.profiles p
  WHERE lower(p.username) = ANY(names)
    AND p.id <> NEW.user_id
    AND public.notif_pref_enabled(p.id, 'mention');

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_rec_mention ON public.recommendation_comments;
CREATE TRIGGER trg_notify_rec_mention
AFTER INSERT ON public.recommendation_comments
FOR EACH ROW EXECUTE FUNCTION public.tg_notify_rec_mention();

DROP TRIGGER IF EXISTS trg_notify_blast_mention ON public.request_comments;
CREATE TRIGGER trg_notify_blast_mention
AFTER INSERT ON public.request_comments
FOR EACH ROW EXECUTE FUNCTION public.tg_notify_blast_mention();