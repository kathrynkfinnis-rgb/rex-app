-- Nov 9 — "we are noticing lots of people have friend requests waiting - can
-- we send a push notification if they are signed up to push to say something
-- like 'you have friend requests waiting...'"
--
-- A friend request already notifies on arrival: notify_friend_request has
-- fired on every insert into friendships since July. So the people sitting on
-- a pile of them were told once, at the moment it arrived, and then never
-- again. That is the gap this fills — not a missing notification, a missing
-- second mention.
--
-- ============================================================ what it sends
-- One notification per person, carrying a count. Never one per request: the
-- whole complaint is that requests accumulate, and six pushes about six
-- requests is how an app gets its notifications switched off for good. The
-- count goes in `data` so the copy can say "3 friend requests waiting"
-- (notifCopy in send-push reads it).
--
-- actor_id is null deliberately. A pile has no single author, and naming one
-- requester of six both misleads and quietly tells you who is in the pile
-- before you have opened it.
--
-- ============================================================== who gets it
-- Three conditions, and each one is a way of not being annoying:
--
--   * the request has been pending at least 3 days. Anything newer was
--     already notified on arrival, and nudging the same day is just the same
--     push twice.
--   * the person has not had this nudge in the last 7 days. Derived from the
--     notifications table itself rather than a new last_nudged column —
--     the row we are about to write is the record, so it may as well be the
--     one we read.
--   * notif_pref_enabled(..., 'friend_request'), the same gate the original
--     notification uses. Someone who turned friend requests off is not
--     waiting to hear a weekly total of them.
--
-- Push is gated separately and later, inside send-push, on push_enabled —
-- so this inserts the in-app row for everyone eligible, and only the people
-- who opted into push get a phone buzz. That is the right split: the bell is
-- not an interruption and does not need the same restraint.
create or replace function public.send_friend_request_nudges()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  sent integer := 0;
begin
  with waiting as (
    select f.addressee_id as user_id, count(*) as pending
      from public.friendships f
     where f.status = 'pending'
       and f.created_at <= now() - interval '3 days'
     group by f.addressee_id
  ), eligible as (
    select w.user_id, w.pending
      from waiting w
     where public.notif_pref_enabled(w.user_id, 'friend_request')
       and not exists (
             select 1
               from public.notifications n
              where n.user_id = w.user_id
                and n.type = 'friend_requests_waiting'
                and n.created_at > now() - interval '7 days'
           )
     -- Bounded, like the ticket reminder job: a first run over a backlog
     -- should not become one burst of several hundred pushes.
     order by w.pending desc
     limit 200
  )
  insert into public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
  select e.user_id, null, 'friend_requests_waiting', 'friendship', null,
         jsonb_build_object('count', e.pending)
    from eligible e;

  get diagnostics sent = row_count;
  return sent;
end;
$$;

revoke all on function public.send_friend_request_nudges() from public, anon, authenticated;

-- Once a day, late morning UTC rather than overnight. A nudge about people
-- waiting to be let in is a daytime thing, and 03:00 is how an app teaches
-- someone to turn push off.
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception
      'pg_cron is not available, so the friend-request nudge would never fire. '
      'Enable it in Supabase under Database > Extensions, then run this again.';
  end if;

  perform cron.unschedule('send-friend-request-nudges')
    where exists (select 1 from cron.job where jobname = 'send-friend-request-nudges');

  perform cron.schedule(
    'send-friend-request-nudges', '0 10 * * *',
    $cron$select public.send_friend_request_nudges();$cron$
  );
end;
$$;
