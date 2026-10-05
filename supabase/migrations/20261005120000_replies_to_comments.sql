-- Oct 5 — "enable replies to comments (like in Instagram), and then also
-- ensure you get notifications for replies to comments — so if I comment on a
-- review, I want to see if someone else comments on that review."
--
-- Two separate things, and the second is the interesting one.
--
-- Replies themselves are a parent_id, the same shape blast replies have had
-- since 7 September: one level only. Instagram is one level too, and the
-- reason is sound — a thread that can nest forever becomes unreadable on a
-- phone, and a reply to a reply almost always belongs to the same
-- conversation as its parent rather than under it.
--
-- The notification is the part that makes a comment thread work at all. Until
-- now only the Rex's owner heard about a comment, so two people could have a
-- conversation under somebody's recommendation and neither would know the
-- other had answered. Commenting on something is an expression of interest in
-- it, so anyone who has commented hears about later comments — which is what
-- "if I comment on a review, I want to see if someone else comments" asks for.
--
-- Deliberately reusing the rec_comment preference rather than adding a switch.
-- To the person receiving it this is the same kind of event, and a second
-- toggle for "comments, but the ones that aren't yours" is a worse setting
-- than no setting.

alter table public.recommendation_comments
  add column if not exists parent_id uuid references public.recommendation_comments(id) on delete cascade;

alter table public.want_comments
  add column if not exists parent_id uuid references public.want_comments(id) on delete cascade;

create index if not exists recommendation_comments_parent_idx
  on public.recommendation_comments(parent_id) where parent_id is not null;
create index if not exists want_comments_parent_idx
  on public.want_comments(parent_id) where parent_id is not null;

comment on column public.recommendation_comments.parent_id is
  'The comment this replies to. One level only — a reply to a reply hangs off the same parent.';

-- Everyone already talking under this Rex, told about a new comment.
--
-- The owner is excluded because tg_notify_rec_comment already tells them, and
-- two notifications for one comment is exactly the double we spent today
-- removing. The author of the new comment is excluded for the obvious reason.
CREATE OR REPLACE FUNCTION public.tg_notify_comment_thread()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  owner_id uuid;
  participant uuid;
BEGIN
  SELECT user_id INTO owner_id FROM public.recommendations WHERE id = NEW.recommendation_id;

  FOR participant IN
    SELECT DISTINCT c.user_id
    FROM public.recommendation_comments c
    WHERE c.recommendation_id = NEW.recommendation_id
      AND c.id <> NEW.id
      AND c.user_id <> NEW.user_id
      AND c.user_id IS DISTINCT FROM owner_id
  LOOP
    CONTINUE WHEN NOT public.notif_pref_enabled(participant, 'rec_comment');

    INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
    VALUES (
      participant, NEW.user_id, 'rec_comment_thread', 'recommendation', NEW.recommendation_id,
      jsonb_build_object('preview', left(coalesce(NEW.body, ''), 120))
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_comment_thread ON public.recommendation_comments;
CREATE TRIGGER notify_comment_thread AFTER INSERT ON public.recommendation_comments
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_comment_thread();
