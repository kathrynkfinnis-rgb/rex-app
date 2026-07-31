DROP POLICY IF EXISTS "rec-photos read for authenticated" ON storage.objects;

CREATE POLICY "rec-photos owner or friends read"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'rec-photos'
  AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.are_friends(auth.uid(), ((storage.foldername(name))[1])::uuid)
  )
);