REVOKE ALL ON FUNCTION public.tg_notify_rec_mention() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tg_notify_blast_mention() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notif_pref_enabled(uuid, text) FROM PUBLIC, anon, authenticated;