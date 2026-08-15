-- Safety net for the native importer (#109/#15/#38). The web app's
-- extractFromText/approveRow (src/lib/import.functions.ts) already reference
-- raw_section and raw_url on import_staging, but no migration file in this
-- repo shows them being added — they were most likely added directly via
-- Lovable's schema tool rather than a tracked migration (the same situation
-- published_at was in earlier this session, where the column already existed
-- live before the migration for it was written here). IF NOT EXISTS makes
-- this safe to run whether or not that's the case.
ALTER TABLE public.import_staging ADD COLUMN IF NOT EXISTS raw_section text;
ALTER TABLE public.import_staging ADD COLUMN IF NOT EXISTS raw_url text;
