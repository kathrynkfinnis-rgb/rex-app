-- Nov 19 — "can we please update to requests 12 hours old."
--
-- The nudge about friend requests waiting to be answered went out for
-- requests pending at least 3 days. During a ramp-up that is far too patient:
-- the people being invited now are the ones deciding whether Rex is worth
-- keeping, and a request sitting unanswered for three days has usually been
-- forgotten by both ends by the time anybody is reminded of it.
--
-- Twelve hours instead. The original reasoning for the delay still holds and
-- is why this is twelve rather than one: the addressee was already notified
-- the moment the request arrived, so nudging in the same hour is the same
-- push twice. Twelve hours clears that — a request made in the evening is
-- nudged the next morning, which is the behaviour being asked for.
--
-- The cooldown between repeat nudges goes from 7 days to 2 at the same time.
-- These are two different dials and it is worth being clear which is which:
-- the twelve hours decides how soon the first reminder comes after a request
-- arrives, and this decides how often somebody who keeps ignoring it hears
-- again. Weekly was tuned for a steady state that does not exist yet; during
-- a ramp-up the requests are the product working, and two days is the
-- difference between a reminder and a footnote.
--
-- Worth knowing what it buys and what it costs. A person sitting on requests
-- now hears about them roughly three times a week instead of once. That is
-- the intent. It is also the fastest way to make somebody turn push off, and
-- right now only three of the eight people nudged in the last two days can
-- receive a push at all — so if this does start reaching phones, this number
-- is the first one to look at again.
--
-- Deliberately NOT changed:
--
--   * The 200-row cap, the preference gate, and the null actor_id. All three
--     are unrelated to timing.
--   * The schedule. '0 10 * * *' is already 10:00 GMT, which is what was
--     asked for. Worth knowing it is pinned to UTC, so between late March and
--     late October it lands at 11:00 British Summer Time. Fixing that
--     properly means a timezone-aware schedule rather than a cron string, and
--     it is not worth doing for one hour twice a year.
--
-- Only the function is replaced. The cron entry already points at it by name,
-- so it picks this up on its next run with nothing else to do.

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
       -- Nov 19: was '3 days'.
       and f.created_at <= now() - interval '12 hours'
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
                -- Nov 19: was '7 days'.
                and n.created_at > now() - interval '2 days'
           )
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
