-- Security review (Aug 25) turned up a live bug: AddRexView's "Post
-- anonymously" toggle (#78) sets is_anonymous on the INSERT body
-- unconditionally (RexAPI.createRecommendation), but no migration ever
-- added an is_anonymous column to public.recommendations — only
-- public.feedback got one (20260730184359). Right now, toggling "Post
-- anonymously" makes the post fail outright: PostgREST rejects the INSERT
-- for referencing a column that doesn't exist, surfaced to the user as
-- "Couldn't post your Rex."
--
-- This migration adds the column so the toggle actually works. It does
-- NOT by itself make posts anonymous to other API callers — see the
-- security review notes on get_shared_recommendation and the plain
-- recommendations SELECT policy, both of which still return the real
-- user_id/author fields regardless of this flag. That's a separate,
-- bigger design decision (a masking view/RPC) flagged in the review
-- rather than folded into this fix.

ALTER TABLE public.recommendations
  ADD COLUMN IF NOT EXISTS is_anonymous boolean NOT NULL DEFAULT false;
