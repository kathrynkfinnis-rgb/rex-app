-- Oct 14 — "I would also like to be able to add a short note alongside each
-- item on a list."
--
-- Not the same thing as the Rex's own note, which is why it needs its own
-- column rather than reusing one. A Rex's note is what you thought of the
-- place: "tiny room, book ahead". A note on a list entry is what you want
-- whoever reads the list to do about it: "get the crab sandwich", "Tuesdays
-- only", "ask for the table at the back". The same place can sit in three
-- lists wanting three different things said about it, and it can carry a note
-- in somebody's list without you having Rex'd it at all.
--
-- Deliberately short. This is an annotation beside a row, not a second review:
-- the row it decorates is one line tall, and a paragraph there would bury the
-- thing it is about.
alter table public.saved_posts
  add column if not exists note text;

comment on column public.saved_posts.note is
  'A short note from whoever put this on the list — what to do about it, not what they thought of it. The Rex''s own note is on recommendations.';

-- A want sitting in a collection is a `wants` row wearing a SavedPost's
-- clothes (see fetchCollectionItems), so its heading and position already live
-- on differently-named columns of a different table. Its note does too.
alter table public.wants
  add column if not exists list_note text;

comment on column public.wants.list_note is
  'The wants half of saved_posts.note — a short note beside this want where it sits in a collection.';

-- Both tables already grant UPDATE to authenticated for the ordering work, so
-- nothing new is needed there; writing a note is the same permission as moving
-- a row, and the existing policies already scope it to your own rows.
