-- Prepared read-only projection. Execute only after release-owner deployment
-- authorization and existing database/schema identity are verified.
-- These columns/predicates match the current web and mini-program public feed.
SELECT id::text AS id, title, COALESCE(description, '') AS description
FROM public.works
WHERE visibility = 'public'
  AND moderation_status = 'ok'
  AND deleted_at IS NULL
  AND published_at IS NOT NULL;
