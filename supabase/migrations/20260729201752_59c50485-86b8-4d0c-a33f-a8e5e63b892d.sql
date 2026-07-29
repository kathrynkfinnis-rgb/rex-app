
ALTER TABLE public.recommendations
  ADD COLUMN IF NOT EXISTS photo_urls text[] NOT NULL DEFAULT '{}'::text[];

-- Storage RLS for the rec-photos bucket. First path segment is the owner user id.
CREATE POLICY "rec-photos read for authenticated"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'rec-photos');

CREATE POLICY "rec-photos owner upload"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'rec-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "rec-photos owner update"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'rec-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "rec-photos owner delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'rec-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
