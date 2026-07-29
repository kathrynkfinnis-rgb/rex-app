
-- ============ Tables ============
CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,               -- recipient
  actor_id uuid,                       -- who triggered it
  type text NOT NULL,                  -- 'rec_like' | 'rec_comment' | 'friend_request' | 'friend_accepted' | 'blast_new' | 'blast_comment' | 'friend_new_rec'
  entity_type text,                    -- 'recommendation' | 'request' | 'friendship' | 'profile'
  entity_id uuid,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_created_idx ON public.notifications(user_id, created_at DESC);
CREATE INDEX notifications_user_unread_idx ON public.notifications(user_id) WHERE read_at IS NULL;

GRANT SELECT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own notifications" ON public.notifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users update own notifications" ON public.notifications
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users delete own notifications" ON public.notifications
  FOR DELETE TO authenticated USING (auth.uid() = user_id);
-- INSERT only via SECURITY DEFINER triggers, no policy needed for authenticated.

CREATE TABLE public.notification_preferences (
  user_id uuid PRIMARY KEY,
  rec_like boolean NOT NULL DEFAULT true,
  rec_comment boolean NOT NULL DEFAULT true,
  friend_request boolean NOT NULL DEFAULT true,
  friend_accepted boolean NOT NULL DEFAULT true,
  blast_new boolean NOT NULL DEFAULT true,
  blast_comment boolean NOT NULL DEFAULT true,
  friend_new_rec boolean NOT NULL DEFAULT false,
  email_enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.notification_preferences TO authenticated;
GRANT ALL ON public.notification_preferences TO service_role;

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own prefs" ON public.notification_preferences
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users insert own prefs" ON public.notification_preferences
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own prefs" ON public.notification_preferences
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);

CREATE TRIGGER prefs_touch_updated
  BEFORE UPDATE ON public.notification_preferences
  FOR EACH ROW EXECUTE FUNCTION public.tg_touch_updated_at();

-- ============ Helper: check pref (defaults to true when row missing, except friend_new_rec) ============
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

REVOKE ALL ON FUNCTION public.notif_pref_enabled(uuid, text) FROM PUBLIC, anon, authenticated;

-- ============ Triggers ============

-- Like on my rec
CREATE OR REPLACE FUNCTION public.tg_notify_rec_like()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  owner_id uuid;
BEGIN
  SELECT user_id INTO owner_id FROM public.recommendations WHERE id = NEW.recommendation_id;
  IF owner_id IS NULL OR owner_id = NEW.user_id THEN RETURN NEW; END IF;
  IF NOT public.notif_pref_enabled(owner_id, 'rec_like') THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id)
  VALUES (owner_id, NEW.user_id, 'rec_like', 'recommendation', NEW.recommendation_id);
  RETURN NEW;
END;
$$;
CREATE TRIGGER notify_rec_like AFTER INSERT ON public.recommendation_likes
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_rec_like();

-- Comment on my rec
CREATE OR REPLACE FUNCTION public.tg_notify_rec_comment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE owner_id uuid;
BEGIN
  SELECT user_id INTO owner_id FROM public.recommendations WHERE id = NEW.recommendation_id;
  IF owner_id IS NULL OR owner_id = NEW.user_id THEN RETURN NEW; END IF;
  IF NOT public.notif_pref_enabled(owner_id, 'rec_comment') THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
  VALUES (owner_id, NEW.user_id, 'rec_comment', 'recommendation', NEW.recommendation_id,
          jsonb_build_object('preview', left(NEW.body, 140)));
  RETURN NEW;
END;
$$;
CREATE TRIGGER notify_rec_comment AFTER INSERT ON public.recommendation_comments
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_rec_comment();

-- Friend request / accepted
CREATE OR REPLACE FUNCTION public.tg_notify_friend_request()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'pending' AND public.notif_pref_enabled(NEW.addressee_id, 'friend_request') THEN
    INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id)
    VALUES (NEW.addressee_id, NEW.requester_id, 'friend_request', 'friendship', NEW.id);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER notify_friend_request AFTER INSERT ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_friend_request();

CREATE OR REPLACE FUNCTION public.tg_notify_friend_accepted()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'accepted' AND OLD.status <> 'accepted'
     AND public.notif_pref_enabled(NEW.requester_id, 'friend_accepted') THEN
    INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id)
    VALUES (NEW.requester_id, NEW.addressee_id, 'friend_accepted', 'friendship', NEW.id);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER notify_friend_accepted AFTER UPDATE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_friend_accepted();

-- New blast (request) -> notify all friends of the poster
CREATE OR REPLACE FUNCTION public.tg_notify_blast_new()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
  SELECT
    CASE WHEN f.requester_id = NEW.user_id THEN f.addressee_id ELSE f.requester_id END AS friend_id,
    NEW.user_id,
    'blast_new',
    'request',
    NEW.id,
    jsonb_build_object('title', NEW.title)
  FROM public.friendships f
  WHERE f.status = 'accepted'
    AND (f.requester_id = NEW.user_id OR f.addressee_id = NEW.user_id)
    AND public.notif_pref_enabled(
          CASE WHEN f.requester_id = NEW.user_id THEN f.addressee_id ELSE f.requester_id END,
          'blast_new'
        );
  RETURN NEW;
END;
$$;
CREATE TRIGGER notify_blast_new AFTER INSERT ON public.requests
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_blast_new();

-- Comment / suggestion on my blast
CREATE OR REPLACE FUNCTION public.tg_notify_blast_comment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE owner_id uuid; owner_title text;
BEGIN
  SELECT user_id, title INTO owner_id, owner_title FROM public.requests WHERE id = NEW.request_id;
  IF owner_id IS NULL OR owner_id = NEW.user_id THEN RETURN NEW; END IF;
  IF NOT public.notif_pref_enabled(owner_id, 'blast_comment') THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
  VALUES (owner_id, NEW.user_id, 'blast_comment', 'request', NEW.request_id,
          jsonb_build_object('preview', left(NEW.body, 140), 'title', owner_title,
                             'has_suggestion', NEW.suggested_item_id IS NOT NULL));
  RETURN NEW;
END;
$$;
CREATE TRIGGER notify_blast_comment AFTER INSERT ON public.request_comments
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_blast_comment();

-- New recommendation from a friend (opt-in, off by default)
CREATE OR REPLACE FUNCTION public.tg_notify_friend_new_rec()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item_title text;
BEGIN
  SELECT title INTO item_title FROM public.items WHERE id = NEW.item_id;
  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
  SELECT
    CASE WHEN f.requester_id = NEW.user_id THEN f.addressee_id ELSE f.requester_id END AS friend_id,
    NEW.user_id,
    'friend_new_rec',
    'recommendation',
    NEW.id,
    jsonb_build_object('title', item_title)
  FROM public.friendships f
  WHERE f.status = 'accepted'
    AND (f.requester_id = NEW.user_id OR f.addressee_id = NEW.user_id)
    AND public.notif_pref_enabled(
          CASE WHEN f.requester_id = NEW.user_id THEN f.addressee_id ELSE f.requester_id END,
          'friend_new_rec'
        );
  RETURN NEW;
END;
$$;
CREATE TRIGGER notify_friend_new_rec AFTER INSERT ON public.recommendations
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_friend_new_rec();

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
