-- Oct 12 — "can we have a push the day before and 30 mins before, but make
-- these editable."
--
-- The first version stored one reminder per person per event, which cannot
-- hold two. The shape that can is one row per timing: each has its own
-- remind_at and its own notified_at, so each fires exactly once and editing
-- the set is adding and removing rows rather than rewriting a list and working
-- out which parts of it have already gone out.
--
-- lead_minutes is stored alongside remind_at even though one implies the other
-- given the event's time. It is what the person chose, and remind_at is when
-- that worked out to — so if an on-sale time is corrected later, the app can
-- recompute every reminder from what they asked for instead of guessing their
-- intent back out of a timestamp.
--
-- Safe whether or not this morning's migration has been run: everything here
-- is guarded, and a database that already has the one-reminder table gets its
-- existing rows treated as the 30-minute reminder they were.
alter table public.ticket_reminders
  add column if not exists lead_minutes integer not null default 30;

comment on column public.ticket_reminders.lead_minutes is
  'How far before the on-sale time this reminder fires, in minutes — 1440 for the day before, 30 for the half hour. The person''s choice; remind_at is what it worked out to.';

alter table public.ticket_reminders
  drop constraint if exists ticket_reminders_check_lead;
alter table public.ticket_reminders
  add constraint ticket_reminders_check_lead
  check (lead_minutes between 0 and 43200);

-- One reminder per timing, not one per event. The old constraint allowed only
-- a single row per person per event and is exactly what has to go.
do $$
declare
  old_name text;
begin
  select conname into old_name
    from pg_constraint
   where conrelid = 'public.ticket_reminders'::regclass
     and contype = 'u'
     and pg_get_constraintdef(oid) = 'UNIQUE (user_id, item_id)';
  if old_name is not null then
    execute format('alter table public.ticket_reminders drop constraint %I', old_name);
  end if;
end $$;

create unique index if not exists ticket_reminders_one_per_timing_idx
  on public.ticket_reminders (user_id, item_id, lead_minutes);

-- The due query reads remind_at and notified_at and nothing else, so it needs
-- no changes — two rows due at different times simply come up on different
-- runs. Replaced only to carry the lead through to the notification, so the
-- push can say "tomorrow" rather than making every reminder read the same.
create or replace function public.send_due_ticket_reminders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  sent integer := 0;
begin
  with due as (
    select r.id, r.user_id, r.item_id, r.lead_minutes, i.title, i.tickets_on_sale_at
      from public.ticket_reminders r
      join public.items i on i.id = r.item_id
     where r.notified_at is null
       and r.remind_at <= now()
       and i.tickets_on_sale_at is not null
     order by r.remind_at
     limit 200
  ), marked as (
    update public.ticket_reminders r
       set notified_at = now()
      from due
     where r.id = due.id
    returning r.id
  )
  insert into public.notifications (user_id, actor_id, type, entity_type, entity_id, data)
  select due.user_id, null, 'ticket_reminder', 'item', due.item_id,
         jsonb_build_object(
           'title', due.title,
           'on_sale_at', due.tickets_on_sale_at,
           'lead_minutes', due.lead_minutes
         )
    from due
   where exists (select 1 from marked where marked.id = due.id);

  get diagnostics sent = row_count;
  return sent;
end;
$$;

revoke all on function public.send_due_ticket_reminders() from public, anon, authenticated;
