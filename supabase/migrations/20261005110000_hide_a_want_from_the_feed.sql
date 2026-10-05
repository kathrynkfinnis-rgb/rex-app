-- Oct 5 — "check hide from feed working on all types of Rex."
--
-- It wasn't. The toggle writes recommendations.show_in_feed, and the feed
-- honours it for anything in that table — so a place, a book, a trip and a
-- list are all covered once the save paths pass it (they do now).
--
-- A want isn't in that table. Wants have kept their own since July, and the
-- wants half of the feed is its own query, so a want with the toggle on was
-- quietly posted anyway: the switch looked like it worked and didn't. Same
-- column, same meaning, same null-handling as recommendations.show_in_feed —
-- absent or true shows, only an explicit false hides.
alter table public.wants
  add column if not exists show_in_feed boolean;

comment on column public.wants.show_in_feed is
  'Null or true shows it in the feed; false keeps it off. Matches recommendations.show_in_feed so one toggle governs every kind of Rex.';
