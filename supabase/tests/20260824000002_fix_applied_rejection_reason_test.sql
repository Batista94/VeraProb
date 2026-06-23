BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(3);

-- ── Seeds ────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains,
  dual_control_threshold_cents -- Bypass Dual Control Explicitly!
) VALUES
  ('00000000-0000-0000-0000-0000000008a1', 'Org C', 'Org C SA', '00000000000801',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'c@test.com', 'EXT_AR_C', 'LOGISTICS', ARRAY['testc.com'],
   99999999)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000008e1', '00000000-0000-0000-0000-0000000008a1',
   '00000000-0000-0000-0000-0000000008f1', 'set-overturn-08',
   '00000000-0000-0000-0000-0000000008aa', '{"fine_cents": 5000}'::jsonb, 'disputed');

INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000008bb',
        '00000000-0000-0000-0000-0000000008a1',
        '00000000-0000-0000-0000-0000000008aa')
ON CONFLICT DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES 
  ('00000000-0000-0000-0000-0000000008cc',
   '00000000-0000-0000-0000-0000000008bb',
   'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
   '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000008b1","organization_id":"00000000-0000-0000-0000-0000000008a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000008a1","role":"AUDITOR"}}';

SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000008a1',
       '00000000-0000-0000-0000-0000000008e1',
       'DISPUTE_OVERTURNED',
       'Justificativa de que a multa procede.',
       '00000000-0000-0000-0000-0000000008b1', 'auditor-c@test.com',
       '2026-08-24T12:05:00Z',
       'idem-08e1-overturn',
       'FORCE_MAJEURE'
     ) $$,
  'T1: resolve_dispute DISPUTE_OVERTURNED runs successfully'
);

SELECT is(
  (SELECT rejection_reason FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000008e1'),
  'Justificativa de que a multa procede.',
  'T2: rejection_reason is correctly preserved in sanction_review_queue for applied status'
);

SELECT diag('DUMPING FORENSIC SNAPSHOTS FOR QUEUE ENTRY:');
SELECT diag(row_to_json(t)::text) FROM (
  SELECT id, queue_entry_id, ledger_entry_id FROM public.forensic_evidence_snapshots
  WHERE organization_id = '00000000-0000-0000-0000-0000000008a1'
) t;

SELECT lives_ok(
  $$ SELECT public.verify_forensic_evidence_by_queue(
            '00000000-0000-0000-0000-0000000008a1',
            '00000000-0000-0000-0000-0000000008e1'
          ) $$,
  'T3: queue_entry_id was populated correctly, verify_forensic_evidence_by_queue finds it without throwing P0002'
);

SELECT * FROM finish();
ROLLBACK;
