-- Sept 7 — "it would be nice to 'like' or reply to someone's Rex on your
-- blast."
--
-- A blast response is a row in request_comments, which is a flat list: no
-- likes, and no way to answer one. The whole point of a blast is the
-- back-and-forth ("fritters but they're so messy to make" deserves a reply),
-- and right now the only way to respond is another top-level suggestion,
-- which reads as a new answer rather than a reply to one.
--
-- Two additions, both the same shape as the ones wants got on 5 Sept:
--   * request_comment_likes — a like on one suggestion
--   * request_comments.parent_id — a reply to one, threaded one level deep

create table if not exists public.request_comment_likes (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references public.request_comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (comment_id, user_id)
);

create index if not exists request_comment_likes_comment_idx
  on public.request_comment_likes (comment_id);

alter table public.request_comment_likes enable row level security;

-- Same rule as want_likes: if you can see the suggestion, you can see who
-- liked it. Anything stricter shows a count that doesn't match the faces.
drop policy if exists "request_comment_likes readable with the comment" on public.request_comment_likes;
create policy "request_comment_likes readable with the comment"
  on public.request_comment_likes for select
  using (exists (select 1 from public.request_comments c where c.id = comment_id));

drop policy if exists "request_comment_likes are your own to write" on public.request_comment_likes;
create policy "request_comment_likes are your own to write"
  on public.request_comment_likes for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- One level of threading, not arbitrary nesting: a suggestion and the
-- replies to it. Deeper trees are a lot of interface for a conversation
-- that is, in practice, "which one did you mean?" and an answer.
alter table public.request_comments
  add column if not exists parent_id uuid references public.request_comments(id) on delete cascade;

create index if not exists request_comments_parent_idx
  on public.request_comments (parent_id, created_at);
