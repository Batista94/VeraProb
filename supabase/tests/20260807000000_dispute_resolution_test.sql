BEGIN;
SELECT plan(36);

-- 1. Index exists
SELECT has_index(
  'public',
  'sanction_review_queue',
  'idx_srq_org_status_concluded_at',
  'sanction_review_queue has partial index on completed status'
);

-- 2. Index is partial
SELECT ok(
  (SELECT indexdef FROM pg_indexes WHERE indexname = 'idx_srq_org_status_concluded_at') LIKE '%applied%' AND
  (SELECT indexdef FROM pg_indexes WHERE indexname = 'idx_srq_org_status_concluded_at') LIKE '%rejected%',
  'idx_srq_org_status_concluded_at is a partial index filtering by status'
);

-- 3. Constraint exists
SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_type ty
    JOIN pg_namespace n ON n.oid = ty.typnamespace
    WHERE n.nspname = 'public' AND ty.typname = 'ledger_event_type'
  ),
  'ledger_event_type enum exists (replaces chk_ledger_type)'
);

-- Setup: organization required for inserts
INSERT INTO public.organizations (id, name, cnpj, created_at)
VALUES ('c1000000-0000-0000-0000-00000000000c', 'Ledger Test Corp', '11.222.333/0001-44', NOW())
ON CONFLICT (id) DO NOTHING;

-- 4. Constraint rejects invalid type
SELECT throws_ok(
  $$INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, contract_id, plan_version, occurred_at_utc, payload) 
    VALUES ('c1000000-0000-0000-0000-00000000000c', 'INVALID_LEDGER_TYPE_XYZ', 'a0000000-0000-0000-0000-0000000000a1', 1, NOW(), '{"verdict_evidence": {}}'::jsonb)$$,
  '22P02',
  NULL,
  'ENUM rejects invalid ledger type with 22P02 (invalid_text_representation)'
);

-- 5-36. lives_ok for all 32 valid types
SELECT lives_ok(
  format(
    $$INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, contract_id, plan_version, occurred_at_utc, payload) 
      VALUES ('c1000000-0000-0000-0000-00000000000c', %L, 'a0000000-0000-0000-0000-0000000000a1', 1, NOW(), '{"verdict_evidence": {}}'::jsonb)$$,
    t
  ),
  format('Ledger accepts valid type: %s', t)
) FROM unnest(ARRAY[
  'EXECUTION_BOUND',
  'NO_SHOW_DECLARED',
  'EVIDENCE_GAP_DECLARED',
  'PLAN_DECLARED',
  'OCCURRENCE_REGISTERED',
  'TRIP_INTERRUPTED',
  'TRIP_CANCELLED',
  'CONTRACT_CREATED',
  'CONTRACT_ACTIVATED',
  'CONTRACT_CLOSED',
  'CONTRACT_SUBMITTED_FOR_APPROVAL',
  'CONTRACT_ACCEPTED_BY_CONTRACTOR',
  'SANCTION_RECOMMENDED',
  'VERDICT_SEALED',
  'VERDICT_REFUSED',
  'SANCTION_DISPUTED',
  'DISPUTE_ACCEPTED',
  'DISPUTE_OVERTURNED',
  'DISPUTE_RETRACTED',
  'JUSTIFICATION_SUBMITTED',
  'JUSTIFICATION_APPROVED',
  'JUSTIFICATION_REJECTED',
  'SLA_JUSTIFICATION_SUBMITTED',
  'SLA_JUSTIFICATION_EXPIRED',
  'TRANSIT_STARTED',
  'COMPLETED_WITH_GAPS',
  'EXECUTION_INHIBITED',
  'UNKNOWN_EVENT',
  'MAX_TOLERANCE_DELAY',
  'MAX_EVIDENCE_GAP',
  'MIN_GEOFENCE_COVERAGE',
  'NO_SHOW_PENALTY'
]) AS t;

SELECT * FROM finish();
ROLLBACK;
