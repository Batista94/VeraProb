-- pr_scanner: ignore-regression (companion test for 20260822000004)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(3);

-- =============================================================================
-- pgTAP: portal_delete_triggers_honor_test_cleanup_guc companion test
-- Migration: 20260822000004_portal_delete_triggers_honor_test_cleanup_guc.sql
-- Focus: With a live row in EVERY dispute-portal append-only table,
--        test_cleanup_forensic_data must complete (no restrict_violation) and
--        empty all FK children + sanction_review_queue. Regression guard for the
--        six prevent_*_delete triggers honoring vera.authorized_test_cleanup.
-- INV-1, INV-3, INV-22.
-- =============================================================================

INSERT INTO public.organizations (id, name, cnpj) VALUES
  ('ee000000-0000-0000-0000-000000000011'::uuid, 'EE Trigger GUC Test Org', '44444444444402')
ON CONFLICT (id) DO NOTHING;

-- Parent queue row (INSERT not blocked by append-only trigger)
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'ee000000-0000-0000-0000-000000000021'::uuid,
  'ee000000-0000-0000-0000-000000000011'::uuid,
  'ee000000-0000-0000-0000-000000000f21'::uuid,
  'set-ee2', 'ee-contract-2',
  jsonb_build_object('fine_cents', 10000,
                     'primary_evidence_timestamp_utc', '2026-08-22T10:00:00Z'),
  'pending', 'EE-002'
);

-- Portal token (FK target for evidence/justification/acknowledgement children)
INSERT INTO public.dispute_portal_tokens
  (id, token, organization_id, queue_entry_id, created_by_user_id,
   expires_at_utc, max_access_count, created_at_utc)
VALUES (
  'ee000000-0000-0000-0000-0000000000d1'::uuid,
  'ee000000-0000-0000-0000-0000000000d2'::uuid,
  'ee000000-0000-0000-0000-000000000011'::uuid,
  'ee000000-0000-0000-0000-000000000021'::uuid,
  'ee000000-0000-0000-0000-0000000000a2'::uuid,
  NOW() + INTERVAL '24 hours', 5, NOW()
);

-- FK child: dispute_evidence_attachments
INSERT INTO public.dispute_evidence_attachments
  (organization_id, queue_entry_id, storage_path, file_name, mime_type,
   file_size_bytes, sha256_hash, uploaded_by)
VALUES (
  'ee000000-0000-0000-0000-000000000011'::uuid,
  'ee000000-0000-0000-0000-000000000021'::uuid,
  'org/queue/evidence.png', 'evidence.png', 'image/png',
  1024, repeat('a', 64),
  'ee000000-0000-0000-0000-0000000000a3'::uuid
);

-- FK child: portal_evidence_submissions
INSERT INTO public.portal_evidence_submissions
  (organization_id, queue_entry_id, token_id, quarantine_storage_path,
   file_name, mime_type_declared, file_size_bytes_declared, sha256_client)
VALUES (
  'ee000000-0000-0000-0000-000000000011'::uuid,
  'ee000000-0000-0000-0000-000000000021'::uuid,
  'ee000000-0000-0000-0000-0000000000d1'::uuid,
  'token/quarantine.png', 'quarantine.png', 'image/png',
  2048, repeat('b', 64)
);

-- FK child: portal_justification_submissions
INSERT INTO public.portal_justification_submissions
  (organization_id, queue_entry_id, token_id, justification_text,
   sha256_justification_seal)
VALUES (
  'ee000000-0000-0000-0000-000000000011'::uuid,
  'ee000000-0000-0000-0000-000000000021'::uuid,
  'ee000000-0000-0000-0000-0000000000d1'::uuid,
  'Contestacao formal de teste com texto suficiente.', repeat('c', 64)
);

-- FK child: sanction_acknowledgements (INTERNAL_RECORD — no token/hash required)
INSERT INTO public.sanction_acknowledgements
  (organization_id, queue_entry_id, acknowledgement_method, acknowledged_by_user_id)
VALUES (
  'ee000000-0000-0000-0000-000000000011'::uuid,
  'ee000000-0000-0000-0000-000000000021'::uuid,
  'INTERNAL_RECORD', 'ee000000-0000-0000-0000-0000000000a4'::uuid
);

-- FK child: sanction_escalation_log
INSERT INTO public.sanction_escalation_log
  (organization_id, queue_entry_id, channel)
VALUES (
  'ee000000-0000-0000-0000-000000000011'::uuid,
  'ee000000-0000-0000-0000-000000000021'::uuid,
  'in_app'
);

-- T1: cleanup completes — all six append-only DELETE triggers honor the GUC
SELECT lives_ok(
  $$ SELECT public.test_cleanup_forensic_data('ee000000-0000-0000-0000-000000000011'::uuid) $$,
  'T1: no restrict_violation — portal append-only triggers honor authorized_test_cleanup'
);

-- T2: sanction_review_queue emptied for the test org
SELECT is(
  (SELECT COUNT(*)::int FROM public.sanction_review_queue
   WHERE organization_id = 'ee000000-0000-0000-0000-000000000011'::uuid),
  0,
  'T2: sanction_review_queue emptied after cleanup'
);

-- T3: every dispute-portal FK child emptied for the test org
SELECT is(
  (SELECT
     (SELECT COUNT(*) FROM public.dispute_evidence_attachments     WHERE organization_id = 'ee000000-0000-0000-0000-000000000011'::uuid)
   + (SELECT COUNT(*) FROM public.portal_evidence_submissions      WHERE organization_id = 'ee000000-0000-0000-0000-000000000011'::uuid)
   + (SELECT COUNT(*) FROM public.portal_justification_submissions WHERE organization_id = 'ee000000-0000-0000-0000-000000000011'::uuid)
   + (SELECT COUNT(*) FROM public.sanction_acknowledgements        WHERE organization_id = 'ee000000-0000-0000-0000-000000000011'::uuid)
   + (SELECT COUNT(*) FROM public.dispute_portal_tokens            WHERE organization_id = 'ee000000-0000-0000-0000-000000000011'::uuid)
   + (SELECT COUNT(*) FROM public.sanction_escalation_log          WHERE organization_id = 'ee000000-0000-0000-0000-000000000011'::uuid)
  )::int,
  0,
  'T3: all dispute-portal FK children emptied after cleanup'
);

SELECT * FROM finish();
ROLLBACK;
