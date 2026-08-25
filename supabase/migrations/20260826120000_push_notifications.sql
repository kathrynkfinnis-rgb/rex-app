-- #175 — push notifications. Two pieces: a master on/off the user controls
-- from the new native preferences screen (separate from OS-level permission
-- — this is "do you want REX to try", not "did iOS grant it"), and a table
-- of APNs device tokens to actually deliver to. Per-category gating already
-- exists (notification_preferences' rec_like/rec_comment/etc, used today to
-- decide whether an in-app notification row gets created at all) — push
-- reuses those same columns rather than duplicating a second set of toggles.

ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS push_enabled boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.push_tokens (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_token text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_token)
);

GRANT SELECT, INSERT, DELETE ON public.push_tokens TO authenticated;
GRANT ALL ON public.push_tokens TO service_role;

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

-- A user manages their own device's token (registering on sign-in, removing
-- on sign-out/uninstall detection) — nobody needs to read anyone else's.
-- The send-push edge function reads across all users via the service role
-- key, which bypasses RLS entirely, so there's no SELECT policy for
-- `authenticated` at all here.
CREATE POLICY "Users manage own push tokens" ON public.push_tokens
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users remove own push tokens" ON public.push_tokens
  FOR DELETE TO authenticated USING (auth.uid() = user_id);
