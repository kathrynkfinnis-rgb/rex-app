-- Oct 14 — "if I reply on a blast, and then someone else replies, I should
-- also get a notification."
--
-- Answering a blast makes you part of it. The thread carries on without you
-- otherwise: the only person told about a new reply is whoever asked, so the
-- four people who suggested somewhere for the same question never hear what
-- the others said, and a blast reads as four private answers rather than the
-- conversation it is.
--
-- Exactly the shape of notify_comment_thread (5 Oct) for comments under a
-- Rex, against request_comments instead. The blast's owner is excluded
-- because tg_notify_blast_comment already tells them, and two notifications
-- for one reply is the double we have spent a week removing. The author of
-- the new reply is excluded for the obvious reason.
create or replace function public.tg_notify_blast_comment_thread()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  owner_id uuid;
  owner_title text;
  participant uuid;
begin
  select user_id, title into owner_id, owner_title
  from public.requests where id = new.request_id;

  for participant in
    select distinct c.user_id
    from public.request_comments c
    where c.request_id = new.request_id
      and c.id <> new.id
      and c.user_id <> new.user_id
      and c.user_id is distinct from owner_id
  loop
    -- Same preference as the blast owner's own notification: somebody who has
    -- turned blast responses off has turned them off.
    continue when not public.notif_pref_enabled(participant, 'blast_comment');

    insert into public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
    values (
      participant, new.user_id, 'blast_comment_thread', 'request', new.request_id,
      jsonb_build_object('preview', left(coalesce(new.body, ''), 120), 'title', owner_title)
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists notify_blast_comment_thread on public.request_comments;
create trigger notify_blast_comment_thread after insert on public.request_comments
  for each row execute function public.tg_notify_blast_comment_thread();

comment on function public.tg_notify_blast_comment_thread is
  'Tells everyone who has already answered a blast when somebody else answers it. The owner is covered by tg_notify_blast_comment.';
