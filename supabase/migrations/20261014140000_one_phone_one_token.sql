-- Oct 14 — "I'm still getting double push notifications."
--
-- One phone, two rows in push_tokens, so send-push sends to both and the
-- banner arrives twice.
--
-- The primary key is (user_id, device_token), which is the right key for the
-- row and the wrong key for the phone. APNs rotates a device token — on
-- reinstall, on restore from backup, and periodically on its own — and
-- nothing has ever removed the row the old token left behind. Both tokens
-- keep working for a while, so for that while the phone is two devices as far
-- as this table is concerned. Registering again (which the app does on every
-- launch) could only ever add; it had no way to say "this is the same phone
-- as that one", because a token is all it knew.
--
-- So give it something stable to say that with. identifierForVendor survives
-- a token rotation and changes only when every app from this vendor is
-- removed, which is exactly the lifetime a device row should have.
alter table public.push_tokens
  add column if not exists device_id text;

comment on column public.push_tokens.device_id is
  'identifierForVendor — stable across APNs token rotations, so a phone can replace its own old token instead of accumulating rows. Null for rows registered before 14 Oct 2026.';

-- Every existing row predates device_id, so none of them can be matched to a
-- phone, and the duplicates among them cannot be told apart from the live
-- ones. Clearing the table is the honest way out: the app registers on every
-- launch, so each real device puts itself back — once, with its id — the next
-- time it is opened. The cost is that pushes stop until someone opens the
-- app, which for a tester on a build they are actively using is minutes.
delete from public.push_tokens;

-- A phone holds one token. Partial, so the pre-14-Oct nulls could never
-- collide with each other (they are all gone above, but the index should not
-- depend on that).
create unique index if not exists push_tokens_one_per_device
  on public.push_tokens (user_id, device_id)
  where device_id is not null;
