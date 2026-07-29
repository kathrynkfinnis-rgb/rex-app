DROP POLICY IF EXISTS "avatars read by authenticated" ON storage.objects;

CREATE POLICY "avatars read by self, friends, and pending"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (
    -- owner (first path segment is the user's uuid)
    auth.uid()::text = (storage.foldername(name))[1]
    -- accepted friends
    OR public.are_friends(auth.uid(), ((storage.foldername(name))[1])::uuid)
    -- pending friendship in either direction
    OR EXISTS (
      SELECT 1 FROM public.friendships f
      WHERE (
        (f.requester_id = auth.uid() AND f.addressee_id = ((storage.foldername(name))[1])::uuid)
        OR (f.addressee_id = auth.uid() AND f.requester_id = ((storage.foldername(name))[1])::uuid)
      )
    )
  )
);