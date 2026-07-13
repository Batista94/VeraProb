-- pr_scanner: ignore-regression — PR elevation CIA migrations (Council-approved plan)
-- =============================================================================
-- Migration: portal_submissions_unified VIEW (PR5) — read SSOT over twin tables
-- Does NOT drop portal_evidence_submissions / portal_justification_submissions.
-- Freeze: do not expand twin schemas; new fields go behind this view contract.
-- Invariants: INV-2 (security_invoker), INV-22.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE VIEW public.portal_submissions_unified
WITH (security_invoker = true) AS
SELECT
  e.id,
  e.organization_id,
  e.queue_entry_id,
  e.token_id,
  'evidence'::text AS submission_kind,
  e.status,
  e.submitted_at_utc,
  e.deleted_at
FROM public.portal_evidence_submissions e
UNION ALL
SELECT
  j.id,
  j.organization_id,
  j.queue_entry_id,
  j.token_id,
  'justification'::text AS submission_kind,
  j.status,
  j.submitted_at_utc,
  j.deleted_at
FROM public.portal_justification_submissions j;

COMMENT ON VIEW public.portal_submissions_unified IS
  'PR5 unified read of portal evidence + justification submissions. Twin tables frozen for expansion.';

GRANT SELECT ON public.portal_submissions_unified TO authenticated, service_role;
