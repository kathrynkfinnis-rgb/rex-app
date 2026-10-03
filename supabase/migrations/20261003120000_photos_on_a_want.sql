-- Oct 3 — "Can't add a photo to a want-to-try."
--
-- A want has carried a note since September and shows up in the feed as a
-- card like any other, but it had nowhere to put a picture — so the one kind
-- of Rex most likely to come from a screenshot (a menu someone sent you, a
-- book cover, a photo of a shopfront) was the one kind that couldn't hold it.
--
-- Same column name and shape as recommendations.photo_urls, so the feed's
-- existing carousel reads a want's photos with no special case.
alter table public.wants
  add column if not exists photo_urls text[];

comment on column public.wants.photo_urls is
  'Photos attached to a want-to-try. Same shape as recommendations.photo_urls so the feed card renders both identically.';
