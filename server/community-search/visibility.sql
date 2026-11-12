-- Extend the existing RPC with a candidate visibility check for the search engine.
-- The deployed search adapter uses OpenSearch BM25 and completion ranking.
-- Existing SQL suggest/search branches remain available through the original RPC.
-- The visible action only revalidates current visibility and block rules.
-- https://help.aliyun.com/zh/analyticdb/analyticdb-for-postgresql/user-guide/pg-trgm
-- https://www.postgresql.org/docs/18/pgtrgm.html
BEGIN;
CREATE OR REPLACE FUNCTION public.community_search(p_action text, p_query text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  query_text text := lower(btrim(p_query));
  literal_pattern text;
  response jsonb;
  viewer_id uuid := auth.uid();
  blocked_author_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  IF p_action IS NULL OR p_action NOT IN ('suggest', 'search', 'visible')
      OR query_text IS NULL OR char_length(query_text) NOT BETWEEN 1 AND (CASE WHEN p_action = 'visible' THEN 4096 ELSE 128 END) THEN
    RAISE EXCEPTION 'invalid_query' USING ERRCODE = '22023';
  END IF;
  -- Anonymous callers have no SELECT privilege on blocks. This statement is
  -- prepared/executed only for an authenticated viewer, using that viewer's RLS.
  IF viewer_id IS NOT NULL THEN
    SELECT COALESCE(array_agg(b.blocked_id) FILTER (WHERE b.blocked_id IS NOT NULL), ARRAY[]::uuid[])
      INTO blocked_author_ids
      FROM public.blocks AS b
      WHERE b.blocker_id = viewer_id;
  END IF;
  IF p_action = 'visible' THEN
    IF jsonb_typeof(p_query::jsonb) <> 'array' OR jsonb_array_length(p_query::jsonb) > 100 THEN
      RAISE EXCEPTION 'invalid_query' USING ERRCODE = '22023';
    END IF;
    SELECT jsonb_build_object('works', COALESCE(jsonb_agg(jsonb_build_object('id', w.id, 'title', w.title)), '[]'::jsonb))
      INTO response
      FROM public.works AS w
      WHERE w.visibility = 'public' AND w.moderation_status = 'ok'
        AND w.deleted_at IS NULL AND w.published_at IS NOT NULL
        AND w.user_id <> ALL(blocked_author_ids)
        AND w.id IN (SELECT value::uuid FROM jsonb_array_elements_text(p_query::jsonb));
    RETURN response;
  END IF;
  -- LIKE special characters remain literal user text. This is SQL escaping,
  -- independent of the installed extension's ranking implementation.
  literal_pattern := replace(replace(replace(query_text, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_');
  IF p_action = 'suggest' THEN
    SELECT jsonb_build_object('suggestions', COALESCE(jsonb_agg(candidate.title ORDER BY candidate.score DESC, candidate.title), '[]'::jsonb))
      INTO response
      FROM (
        SELECT DISTINCT w.title, public.similarity(lower(w.title), query_text) AS score
        FROM public.works AS w
        WHERE w.visibility = 'public' AND w.moderation_status = 'ok'
          AND w.deleted_at IS NULL AND w.published_at IS NOT NULL
          AND w.user_id <> ALL(blocked_author_ids)
          AND lower(w.title) LIKE literal_pattern || '%' ESCAPE E'\\'
        ORDER BY score DESC, w.title
        LIMIT 10
      ) AS candidate;
  ELSE
    SELECT jsonb_build_object('works', COALESCE(jsonb_agg(jsonb_build_object('id', candidate.id) ORDER BY candidate.score DESC, candidate.id), '[]'::jsonb))
      INTO response
      FROM (
        SELECT w.id, public.similarity(lower(concat_ws(' ', w.title, w.description)), query_text) AS score
        FROM public.works AS w
        WHERE w.visibility = 'public' AND w.moderation_status = 'ok'
          AND w.deleted_at IS NULL AND w.published_at IS NOT NULL
          AND w.user_id <> ALL(blocked_author_ids)
          AND (lower(w.title) LIKE '%' || literal_pattern || '%' ESCAPE E'\\'
            OR lower(w.description) LIKE '%' || literal_pattern || '%' ESCAPE E'\\')
        ORDER BY score DESC, w.id
        LIMIT 20
      ) AS candidate;
  END IF;
  RETURN response;
END;
$function$;
REVOKE ALL ON FUNCTION public.community_search(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.community_search(text, text) TO anon, authenticated;
COMMIT;
