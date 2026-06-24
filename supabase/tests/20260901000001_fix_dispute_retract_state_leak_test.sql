BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- ── Seeds ────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains,
  dual_control_threshold_cents
) VALUES
  ('00000000-0000-0000-0000-0000000001a1', 'Org Retract', 'Org Retract SA', '00000000000101',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'retract@test.com', 'EXT_RET_A', 'LOGISTICS', ARRAY['retract.com'],
   99999999)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000001c1',
        '00000000-0000-0000-0000-0000000001a1',
        '00000000-0000-0000-0000-0000000001aa')
ON CONFLICT DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-0000000001d1',
   '00000000-0000-0000-0000-0000000001c1',
   'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
   '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at, reviewed_at, reviewed_by, rejection_reason)
VALUES
  ('00000000-0000-0000-0000-0000000001e1', '00000000-0000-0000-0000-0000000001a1',
   '00000000-0000-0000-0000-0000000001f1', 'set-retract',
   '00000000-0000-0000-0000-0000000001aa', '{}'::jsonb, 'disputed',
   '2026-06-24T10:00:00Z', '00000000-0000-0000-0000-0000000001b1', '2026-06-25T10:00:00Z',
   '2026-06-24T10:30:00Z', '00000000-0000-0000-0000-0000000001b1', 'Initial dispute reason');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","organization_id":"00000000-0000-0000-0000-0000000001a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000001a1","role":"AUDITOR"}}';

-- 1. Execute resolve_dispute with DISPUTE_RETRACTED.
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000001a1',
       '00000000-0000-0000-0000-0000000001e1',
       'DISPUTE_RETRACTED',
       'Auditor retracted the dispute.',
       '00000000-0000-0000-0000-0000000001b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z',
       'retract-idem-key',
       'FORCE_MAJEURE'
     ) $$,
  'T1: resolve_dispute DISPUTE_RETRACTED runs successfully'
);

-- 2. Verify status changed to pending
SELECT is(
  (SELECT status FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000001e1'),
  'pending',
  'T2: status is reset to pending'
);

-- 3. Verify disputed_at is cleared
SELECT is(
  (SELECT disputed_at FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000001e1'),
  NULL,
  'T3: disputed_at is set to NULL'
);

-- 4. Verify disputed_by is cleared
SELECT is(
  (SELECT disputed_by FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000001e1'),
  NULL,
  'T4: disputed_by is set to NULL'
);

-- 5. Verify resolution_due_at is cleared
SELECT is(
  (SELECT resolution_due_at FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000001e1'),
  NULL,
  'T5: resolution_due_at is set to NULL'
);

-- 6. Verify reviewed_at is cleared (retracted means it was not reviewed/finalized)
SELECT is(
  (SELECT reviewed_at FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000001e1'),
  NULL,
  'T6: reviewed_at is set to NULL'
);

-- 7. Verify ledger entry is written
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-0000000001a1'
      AND type = 'DISPUTE_RETRACTED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000001e1'),
  1,
  'T7: Exactly one DISPUTE_RETRACTED fact appended to the ledger'
);

SELECT * FROM finish();
ROLLBACK;
