-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs (objects don't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: fix test_cleanup_forensic_data FK deletion order
--
-- Dispute portal migrations (20260813–20260818) added tables that FK-reference
-- sanction_review_queue. The previous RPC body deleted sanction_review_queue
-- before its FK-child tables, causing 23503 violations in tearDownAll.
--
-- Correct deletion order (deepest FK children first):
--   1. dispute_evidence_attachments   (→ portal_evidence_submissions, → sanction_review_queue)
--   2. portal_justification_submissions (→ dispute_portal_tokens,      → sanction_review_queue)
--   3. sanction_acknowledgements      (→ dispute_portal_tokens,        → sanction_review_queue)
--   4. portal_evidence_submissions    (→ dispute_portal_tokens,        → sanction_review_queue)
--   5. dispute_portal_tokens          (→ sanction_review_queue)
--   6. sanction_escalation_log        (→ sanction_review_queue)
--   7. sanction_review_queue
-- =============================================================================

CREATE OR REPLACE FUNCTION public.test_cleanup_forensic_data(p_org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Authorize this transaction for test cleanup (scoped to this TX only)
  SET LOCAL vera.authorized_test_cleanup = 'on';

  -- Delete in reverse FK order (Shadow Mode cleanup first)
  DELETE FROM public.shadow_execution_transitions    WHERE organization_id = p_org_id; -- pr_scanner: ignore
  DELETE FROM public.shadow_executions               WHERE organization_id = p_org_id; -- pr_scanner: ignore
  DELETE FROM public.shadow_verdicts                 WHERE organization_id = p_org_id; -- pr_scanner: ignore

  -- Dispute portal FK children — must precede sanction_review_queue
  DELETE FROM public.dispute_evidence_attachments    WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.portal_justification_submissions WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.sanction_acknowledgements       WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.portal_evidence_submissions     WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.dispute_portal_tokens           WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.sanction_escalation_log         WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)

  -- sanction_review_queue (safe — all FK children cleared above)
  DELETE FROM public.sanction_review_queue           WHERE organization_id = p_org_id; -- pr_scanner: ignore

  -- Telegram evidence chain
  DELETE FROM public.telegram_evidence_links         WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_evidence_metadata      WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_evidence_categories    WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_evidence_uploads       WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_chat_bindings          WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_binding_tokens         WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
END;
$$;

-- Preserve: test-only, service_role exclusively
REVOKE ALL ON FUNCTION public.test_cleanup_forensic_data(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.test_cleanup_forensic_data(UUID) TO service_role;

RESET client_min_messages;
