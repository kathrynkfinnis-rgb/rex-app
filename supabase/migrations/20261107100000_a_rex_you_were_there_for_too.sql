-- Nov 7 — "I basically want to be able to repost a friend's rex if I was
-- there too — so people the original rexxer is not friends with would see it
-- from my network."
--
-- A repost relays the original. Your friends see Phoebe's words, Phoebe's
-- rating and Phoebe's photos, attributed to Phoebe, surfaced by you — not
-- your own Rex of the same place crediting her, which was the alternative and
-- was declined.
--
-- That makes this the first thing in Rex that carries somebody's writing past
-- the people they chose to show it to, so the rest of this file is mostly
-- about keeping that one widening from becoming several by accident.

create table if not exists public.reposts (
  id uuid primary key default gen_random_uuid(),
  recommendation_id uuid not null references public.recommendations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  -- "if I was there too" — the reason, optional. A silent relay is still a
  -- repost; this is the "went for my birthday, the leeks are the thing" that
  -- makes it worth more than one.
  note text,
  created_at timestamptz not null default now(),
  -- Reposting the same Rex twice is not a thing. The second one would only
  -- move it back up somebody's feed.
  unique (recommendation_id, user_id)
);

create index if not exists reposts_user_created_idx
  on public.reposts (user_id, created_at desc);
create index if not exists reposts_recommendation_idx
  on public.reposts (recommendation_id);

alter table public.reposts enable row level security;

grant select, insert, delete on public.reposts to authenticated;
grant all on public.reposts to service_role;

-- ───────────────────────────────────────────────────────── who may repost
--
-- One hop, and only one. The author has to be your friend, which means you
-- cannot repost something that reached you by being reposted — otherwise a
-- Rex walks the entire friend graph a hop at a time and "my network" stops
-- meaning anything. Phoebe's Rex reaches your friends; it does not reach
-- theirs unless they were there too and say so themselves.
--
-- The `with check` has to re-state visibility rather than trusting RLS on
-- recommendations to have already decided it. Without it the insert would
-- accept any recommendation id, and since a repost is what makes a row
-- visible, inserting one would grant the inserter sight of a row they were
-- never allowed to see. That is the single attack this table creates, and it
-- is a privilege-escalation-by-guessing-a-uuid if this clause is ever
-- loosened.
create policy "reposts are yours to make" on public.reposts
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.recommendations r
      where r.id = recommendation_id
        and r.published_at is not null
        -- Your own Rex is already in your friends' feeds.
        and r.user_id <> auth.uid()
        and public.are_friends(auth.uid(), r.user_id)
    )
  );

create policy "reposts are yours to undo" on public.reposts
  for delete to authenticated
  using (user_id = auth.uid());

-- Your friends see what you reposted, and so does the person you reposted —
-- they should be able to find out who passed their Rex on, which is the
-- notification below and the count on the card.
create policy "reposts readable by your friends and the author" on public.reposts
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.are_friends(auth.uid(), user_id)
    or exists (
      select 1 from public.recommendations r
      where r.id = reposts.recommendation_id and r.user_id = auth.uid()
    )
  );

-- ──────────────────────────────────────────── seeing a reposted Rex at all
--
-- The actual point of the feature. Everything that reads recommendations
-- inherits this — feed, item page, search, map, profile — the same way
-- published_at's draft rule did in August, and for the same reason: a rule
-- enforced here cannot be forgotten by a query somewhere else.
alter policy "See own and friends' recommendations"
  on public.recommendations
  using (
    auth.uid() = user_id
    or (published_at is not null and public.are_friends(auth.uid(), user_id))
    or (
      published_at is not null
      and exists (
        select 1 from public.reposts rp
        where rp.recommendation_id = recommendations.id
          and (rp.user_id = auth.uid() or public.are_friends(auth.uid(), rp.user_id))
      )
    )
  );

-- The author's name and avatar travel with it. A card attributed to nobody is
-- worse than no card: the whole claim a repost makes is "somebody I know
-- stands behind this", and that needs a name on it.
drop policy if exists "Profiles viewable by self, friends, and pending connections" on public.profiles;
create policy "Profiles viewable by self, friends, and pending connections"
  on public.profiles for select to authenticated
  using (
    auth.uid() = id
    or public.are_friends(auth.uid(), id)
    or exists (
      select 1 from public.friendships f
      where (f.requester_id = auth.uid() and f.addressee_id = profiles.id)
         or (f.addressee_id = auth.uid() and f.requester_id = profiles.id)
    )
    or exists (
      select 1 from public.reposts rp
      join public.recommendations r on r.id = rp.recommendation_id
      where r.user_id = profiles.id
        and (rp.user_id = auth.uid() or public.are_friends(auth.uid(), rp.user_id))
    )
  );

-- ──────────────────────────────────────── what deliberately did NOT widen
--
-- Both of these read "a recommendation I can see" (16 October, closing the
-- hole where you could like or comment on a row by guessing its id). Widening
-- recommendations above would therefore have widened these too, silently: a
-- stranger shown Phoebe's Rex through a repost could comment on it and like
-- it, and Phoebe would get a notification from somebody she has never heard
-- of on a post she wrote for her friends.
--
-- A repost was a decision about who can *see* a Rex. It was not a decision
-- about who can talk to its author, so liking and commenting stay first-
-- degree: yours, or a friend's. This preserves exactly today's behaviour
-- while the read above changes around it.
drop policy if exists "Users insert own likes" on public.recommendation_likes;
create policy "Users insert own likes" on public.recommendation_likes
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.recommendations r
      where r.id = recommendation_id
        and (r.user_id = auth.uid() or public.are_friends(auth.uid(), r.user_id))
    )
  );

drop policy if exists "Users insert own comments" on public.recommendation_comments;
create policy "Users insert own comments" on public.recommendation_comments
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.recommendations r
      where r.id = recommendation_id
        and (r.user_id = auth.uid() or public.are_friends(auth.uid(), r.user_id))
    )
  );

-- ───────────────────────────────────────────────────────────── telling them
--
-- Phoebe finds out. Not optional politeness: her Rex is now in front of
-- people she did not choose, and the least this can do is say so, to her,
-- naming who did it.
alter table public.notification_preferences
  add column if not exists rec_repost boolean not null default true;

create or replace function public.notif_pref_enabled(_user uuid, _type text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
DECLARE
  v boolean;
BEGIN
  SELECT
    CASE _type
      WHEN 'rec_like' THEN rec_like
      WHEN 'rec_comment' THEN rec_comment
      WHEN 'friend_request' THEN friend_request
      WHEN 'friend_accepted' THEN friend_accepted
      WHEN 'blast_new' THEN blast_new
      WHEN 'blast_comment' THEN blast_comment
      WHEN 'friend_new_rec' THEN friend_new_rec
      WHEN 'rec_repost' THEN rec_repost
      ELSE true
    END
  INTO v
  FROM public.notification_preferences
  WHERE user_id = _user;

  IF v IS NULL THEN
    -- default when no prefs row: friend_new_rec off, everything else on
    RETURN _type <> 'friend_new_rec';
  END IF;
  RETURN v;
END;
$$;

create or replace function public.tg_notify_rec_repost()
returns trigger
language plpgsql security definer set search_path = public
as $$
DECLARE
  owner_id uuid;
BEGIN
  SELECT user_id INTO owner_id FROM public.recommendations WHERE id = NEW.recommendation_id;
  IF owner_id IS NULL OR owner_id = NEW.user_id THEN RETURN NEW; END IF;
  IF NOT public.notif_pref_enabled(owner_id, 'rec_repost') THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (user_id, actor_id, type, entity_type, entity_id)
  VALUES (owner_id, NEW.user_id, 'rec_repost', 'recommendation', NEW.recommendation_id);
  RETURN NEW;
END;
$$;

drop trigger if exists notify_rec_repost on public.reposts;
create trigger notify_rec_repost after insert on public.reposts
  for each row execute function public.tg_notify_rec_repost();

-- ──────────────────────────────────────────────────────────── and deletion
--
-- delete_my_account() names every table it clears explicitly, by design, so a
-- new one is invisible to it until it is listed. Reposts you made go with
-- you; reposts of your Rexes go with the recommendation, which already
-- cascades.
comment on table public.reposts is
  'Nov 7 — a friend''s Rex relayed into your network. Add to delete_my_account().';
