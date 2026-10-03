-- Oct 3 — "a notification when someone likes your post."
--
-- Likes on a Rex have notified since July: tg_notify_rec_like fires on
-- recommendation_likes, writes a notifications row, and the webhook on that
-- table sends the push ("X liked your Rex").
--
-- Wants never did. A want-to-try keeps its likes in want_likes (5 Sept, when
-- wants got their own likes and comments tables), and no trigger was ever
-- added there — so liking somebody's want-to-try has always been silent. From
-- the outside that reads as "likes don't notify", which is how it was
-- reported, when in fact it was half the likes in the app.
--
-- Same shape as the Rex version deliberately, including the two guards that
-- matter: never notify someone about their own like, and respect the
-- rec_like preference rather than inventing a second switch for what is, to
-- the person receiving it, the same event.
CREATE OR REPLACE FUNCTION public.tg_notify_want_like()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  owner_id uuid;
BEGIN
  SELECT user_id INTO owner_id FROM public.wants WHERE id = NEW.want_id;
  IF owner_id IS NULL OR owner_id = NEW.user_id THEN RETURN NEW; END IF;
  IF NOT public.notif_pref_enabled(owner_id, 'rec_like') THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id)
  VALUES (owner_id, NEW.user_id, 'rec_like', 'want', NEW.want_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_want_like ON public.want_likes;
CREATE TRIGGER notify_want_like AFTER INSERT ON public.want_likes
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_want_like();
