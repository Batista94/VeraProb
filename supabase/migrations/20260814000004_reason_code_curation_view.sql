-- =============================================================================
-- Migration: reason_code_curation_view (Item 5.5 — Curadoria de reason codes)
-- Surfaces the closed catalogue's support debt: free-text written under any
-- OTHER-category code (OTHER, LEGACY_UNCLASSIFIED) ranked by frequency, so the
-- Product owner can review recurring text and promote it to a global code.
--
-- B6: filter by catalogue CATEGORY ('OTHER'), not a hard-coded code list — the
--     candidate feed survives the addition of new OTHER-bucket codes and stays
--     industry-agnostic (no transport wording here).
-- INV-2 / CI#11: view is security_invoker=true. It carries NO RLS of its own;
--     it inherits the RLS of sanction_review_queue + dispute_reason_codes, so a
--     tenant session sees only its own candidates and the global catalogue. The
--     cross-org aggregate used for GLOBAL promotion runs under service_role
--     (documented in the curation SOP).
-- INV-1/INV-22: organization_id is projected and base-table RLS scopes rows.
-- INV-6: timestamps are TIMESTAMPTZ (first/last seen, UTC).
-- INV-DB: CREATE VIEW is a non-blocking metadata-only DDL (zero-downtime).
-- =============================================================================

-- DROP + CREATE (not CREATE OR REPLACE): guarantees the security_invoker option
-- is applied even if a prior definition existed (CI block #11 caveat).
DROP VIEW IF EXISTS public.v_reason_code_curation_candidates;

CREATE VIEW public.v_reason_code_curation_candidates
  WITH (security_invoker = true)
AS
SELECT
  q.organization_id,
  q.rejection_reason_code                AS reason_code,
  lower(btrim(q.rejection_reason))       AS normalized_text,
  count(*)                               AS occurrence_count,
  min(q.created_at)                      AS first_seen_utc,
  max(q.created_at)                      AS last_seen_utc
FROM public.sanction_review_queue AS q
JOIN public.dispute_reason_codes AS rc
  ON rc.code = q.rejection_reason_code
 AND rc.organization_id IS NULL               -- global catalogue only
WHERE rc.category = 'OTHER'
  AND q.rejection_reason IS NOT NULL
  AND btrim(q.rejection_reason) <> ''
GROUP BY
  q.organization_id,
  q.rejection_reason_code,
  lower(btrim(q.rejection_reason))
ORDER BY occurrence_count DESC, last_seen_utc DESC;

COMMENT ON VIEW public.v_reason_code_curation_candidates IS
  'Item 5.5 curation feed: OTHER-category free-text ranked by frequency per org. '
  'security_invoker=true — inherits base-table RLS. Cross-org promotion view runs '
  'under service_role per the reason-code curation SOP.';

-- INV-DATA-API-GRANT: a view is a new public object with no default privileges.
-- Tenant admins/auditors read their own OTHER backlog (authenticated); the
-- Product owner runs the global cross-org pass under service_role.
GRANT SELECT ON public.v_reason_code_curation_candidates TO authenticated;  -- not anon
GRANT SELECT ON public.v_reason_code_curation_candidates TO service_role;
