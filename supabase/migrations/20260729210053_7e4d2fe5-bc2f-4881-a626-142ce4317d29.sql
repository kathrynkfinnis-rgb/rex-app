CREATE TYPE public.list_visibility AS ENUM ('draft', 'friends', 'public');

ALTER TABLE public.hitlist_lists
  ADD COLUMN visibility public.list_visibility NOT NULL DEFAULT 'draft';

CREATE POLICY "Friends can see friends-visible lists"
  ON public.hitlist_lists FOR SELECT
  TO authenticated
  USING (visibility = 'friends' AND public.are_friends(auth.uid(), user_id));

CREATE POLICY "Anyone signed in can see public lists"
  ON public.hitlist_lists FOR SELECT
  TO authenticated
  USING (visibility = 'public');
