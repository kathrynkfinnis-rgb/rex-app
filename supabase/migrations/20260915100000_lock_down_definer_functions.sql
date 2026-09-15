-- Sept 15 — Supabase security lints (71 warnings): SECURITY DEFINER
-- functions executable by `anon` (logged out) and `authenticated` (any
-- signed-in user) through /rest/v1/rpc/*.
--
-- A SECURITY DEFINER function runs with its owner's rights, not the
-- caller's, which is the whole point for the ones that exist to answer a
-- narrow question RLS would otherwise block. Each one is only as safe as
-- who can call it. Sorted into three groups:
--
-- 1. SERVER ONLY. Nobody should call these through the API at all.
--    * Trigger functions — they fire on inserts/deletes; calling one
--      directly is meaningless at best. Revoking EXECUTE doesn't stop the
--      triggers: Postgres checks that privilege when the trigger is
--      created, not each time it fires.
--    * search_profiles_for / suggested_friends_for — these take the
--      caller's id as an argument (_caller), so anyone able to call them
--      can pass someone else's id and read that person's suggestions. The
--      website only ever calls them from its server with the service role
--      (src/lib/friends.functions.ts), and the app uses the auth.uid()
--      versions (search_profiles, suggested_friends_for_me). A real hole,
--      closed.
--
-- 2. SIGNED-IN ONLY. Fine for any signed-in user, never for a logged-out
--    request: the admin KPIs (which check has_role internally), the RLS
--    helpers, the weekly leaderboard, public collections, view counting.
--
-- 3. LEFT OPEN ON PURPOSE. get_shared_recommendation, get_shared_trip and
--    get_shared_trip_stops back the public share pages (/r/<id>, /t/<id>)
--    that a Rex link opens for someone who isn't on Rex — they have to
--    work logged out. The lint will keep listing them; that's expected.
--    Likewise the signed-in app functions in group 2 and search_profiles,
--    friends_of, match_contact_emails, suggested_friends_for_me and
--    trending_items_weekly stay callable by signed-in users, by design.
--
-- Done by name through pg_proc so it doesn't depend on getting every
-- argument list exactly right, and so a function that doesn't exist in
-- this database is simply skipped.

do $$
declare
  f record;
begin
  -- 1. server only
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (array[
        'handle_new_user',
        'delete_orphaned_container_item',
        'tg_notify_blast_comment', 'tg_notify_blast_mention', 'tg_notify_blast_new',
        'tg_notify_friend_accepted', 'tg_notify_friend_new_rec', 'tg_notify_friend_request',
        'tg_notify_rec_comment', 'tg_notify_rec_like', 'tg_notify_rec_mention',
        'tg_notify_rec_saved', 'tg_notify_rec_tagged',
        'tg_send_push_on_notification',
        'search_profiles_for', 'suggested_friends_for'
      ])
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;

  -- 2. signed-in only
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (array[
        'admin_kpis_content', 'admin_kpis_engagement', 'admin_kpis_users',
        'can_edit_list', 'can_view_list', 'has_role',
        'is_group_member', 'is_group_owner', 'is_list_owner', 'is_rex_curator',
        'notif_pref_enabled',
        'public_collections', 'increment_list_view',
        'top_rexxers_weekly', 'trending_items_weekly'
      ])
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated, service_role', f.sig);
  end loop;
end $$;
