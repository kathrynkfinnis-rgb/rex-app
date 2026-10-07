-- Oct 7 — "Phoebe tried to publish a Rex list via a timer, but it didn't work."
--
-- The scheduling itself was fine: the post was queued with a scheduled_at and
-- a null published_at, exactly as intended. What was missing was anything to
-- come along and publish it.
--
-- publish_due_official_posts() has existed since 18 September, and the
-- migration that created it scheduled a quarter-hourly cron job — but only
-- inside `if exists (select 1 from pg_extension where extname = 'pg_cron')`.
-- That guard was there so the migration wouldn't fail on a database without
-- the extension, which is reasonable, and it meant that on a database without
-- it the job was quietly never created. A queued post then waits for ever,
-- and nothing anywhere says so.
--
-- This enables the extension and schedules the job properly. A guard that
-- skips the important part should at least be loud about it, so if the
-- extension genuinely cannot be created this raises instead of shrugging.
create extension if not exists pg_cron with schema cron;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception
      'pg_cron is not available, so scheduled REX posts will never publish. '
      'Enable it in Supabase under Database > Extensions, then run this again.';
  end if;

  perform cron.unschedule('publish-rex-queue')
    where exists (select 1 from cron.job where jobname = 'publish-rex-queue');

  perform cron.schedule(
    'publish-rex-queue', '*/15 * * * *',
    $cron$select public.publish_due_official_posts();$cron$
  );
end;
$$;

-- Anything already queued and overdue goes out now, rather than waiting up to
-- another quarter of an hour for a job that has only just started existing.
select public.publish_due_official_posts();
