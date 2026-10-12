-- Oct 12 — "can we build a function to offer notifications for upcoming ticket
-- sales for events e.g. Glasto tickets. If someone says 'want to try' on an
-- event, then give them an option to set a reminder for ticket sales if
-- appropriate?"
--
-- Three things, and the first one is the part with no clever answer.
--
-- ============================================ where the on-sale time comes from
-- Nothing we query knows it. Google Places has opening hours, not ticket
-- releases; TMDB and OpenLibrary are the wrong kind of catalogue entirely.
-- There is no feed of "when do tickets for this drop", and inventing one from a
-- web search would be guessing at the single fact the whole feature turns on —
-- a reminder that fires on the wrong day is worse than no reminder, because you
-- trusted it instead of setting your own alarm.
--
-- So a person types it: whoever adds the event, or anyone who edits it
-- afterwards. That also answers her "if appropriate" exactly, and for free —
-- an event with no on-sale time set simply never offers a reminder, which is
-- the right behaviour for the school play and for everything already in the
-- database.
alter table public.items
  add column if not exists tickets_on_sale_at timestamptz;

comment on column public.items.tickets_on_sale_at is
  'When tickets for this event go on sale, as entered by a person — no catalogue publishes this. Null means nobody has said, and the app then offers no reminder.';

-- ================================================================ the reminders
-- Separate from `wants` rather than a column on it. Wanting to go and wanting
-- to be told when tickets drop are different intentions: you can want to go to
-- a festival you already have tickets for, and you can set a reminder for
-- something you are buying for someone else. Keeping them apart also means
-- removing a want never silently cancels an alarm somebody is relying on.
create table if not exists public.ticket_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  -- Stored rather than derived from the item, so that moving an event's
  -- on-sale time doesn't silently retime an alarm somebody has already been
  -- told about — and so a lead time can vary later without a schema change.
  remind_at timestamptz not null,
  -- Set when the notification has gone out. The due query reads this, so a
  -- reminder fires exactly once however often the job runs.
  notified_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, item_id)
);

create index if not exists ticket_reminders_due_idx
  on public.ticket_reminders (remind_at) where notified_at is null;
create index if not exists ticket_reminders_item_idx
  on public.ticket_reminders (item_id);

grant select, insert, delete on public.ticket_reminders to authenticated;
grant all on public.ticket_reminders to service_role;

alter table public.ticket_reminders enable row level security;

-- Friends can see each other's, which is what makes the feed card possible:
-- "Gemma has set a reminder for tickets" is only sayable if you can see that
-- Gemma set one. Same visibility rule as `wants`, for the same reason.
drop policy if exists "See own and friends' ticket reminders" on public.ticket_reminders;
create policy "See own and friends' ticket reminders" on public.ticket_reminders
  for select to authenticated
  using (auth.uid() = user_id or public.are_friends(auth.uid(), user_id));

drop policy if exists "Users set own ticket reminders" on public.ticket_reminders;
create policy "Users set own ticket reminders" on public.ticket_reminders
  for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users cancel own ticket reminders" on public.ticket_reminders;
create policy "Users cancel own ticket reminders" on public.ticket_reminders
  for delete to authenticated
  using (auth.uid() = user_id);

-- ================================================================== firing them
-- Inserting a notifications row is all this has to do: a trigger on that table
-- calls send-push for every insert, so the phone follows from the row. The
-- type is new, and notif_pref_enabled returns true for a type it doesn't
-- recognise, which is the right default here — you asked for this one
-- specifically, so it is not a setting you should have had to find.
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
    select r.id, r.user_id, r.item_id, i.title, i.tickets_on_sale_at
      from public.ticket_reminders r
      join public.items i on i.id = r.item_id
     where r.notified_at is null
       and r.remind_at <= now()
       -- An event whose on-sale time was cleared after the reminder was set
       -- has nothing to remind anybody about. Left unsent rather than
       -- deleted: if the date comes back, so does the reminder.
       and i.tickets_on_sale_at is not null
     -- Oldest first, and a bounded batch, so a backlog after downtime goes
     -- out in order instead of as one burst of a thousand pushes.
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
           'on_sale_at', due.tickets_on_sale_at
         )
    from due
   where exists (select 1 from marked where marked.id = due.id);

  get diagnostics sent = row_count;
  return sent;
end;
$$;

revoke all on function public.send_due_ticket_reminders() from public, anon, authenticated;

-- Every five minutes, not the quarter-hour the publish queue runs on. An
-- on-sale moment is an exact time people set alarms around, and being told
-- fourteen minutes late is being told too late.
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception
      'pg_cron is not available, so ticket reminders would never fire. '
      'Enable it in Supabase under Database > Extensions, then run this again.';
  end if;

  perform cron.unschedule('send-ticket-reminders')
    where exists (select 1 from cron.job where jobname = 'send-ticket-reminders');

  perform cron.schedule(
    'send-ticket-reminders', '*/5 * * * *',
    $cron$select public.send_due_ticket_reminders();$cron$
  );
end;
$$;
