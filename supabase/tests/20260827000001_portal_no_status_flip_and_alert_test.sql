BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

-- =============================================================================
-- pgTAP: portal_no_status_flip_and_alert
-- Migration under test: 20260827000001_portal_no_status_flip_and_alert.sql
--
-- Anti-regression guard (replaces the false-green that let the bug ship):
--   ST1/ST2 FAIL the instant anyone re-introduces the illegal
--   disputed→pending_peer_review flip on the portal submission path.
--   ALERT* prove the operator notification (metadata only — INV-3/9).
--   ZOMBIE proves the portal path never mints an un-confirmable peer-review row.
--   CHK* prove the widened CHECK kept its canonical name (rename-back).
-- Seed UUIDs use only hex chars (d/a/9 + digits).
-- =============================================================================

-- ── Seeds ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000dad9a01','Org9','Org9 SA','00000000dad9a1',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'o9@test.com',
   'EXT9','LOGISTICS',ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- e01 = file-defense queue · e02 = text-defense queue (both disputed).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, vehicle_plate, operator_name, disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-00000dad9e01','00000000-0000-0000-0000-00000dad9a01',
   '00000000-0000-0000-0000-00000dad9f01','set9','00000000-0000-0000-0000-00000dad9aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D","fine_cents":50000}'::jsonb,
   'disputed','ABC1D23','Joao Motorista',
   NOW(),'00000000-0000-0000-0000-00000dad9b01',NOW()+INTERVAL '5 days'),
  ('00000000-0000-0000-0000-00000dad9e02','00000000-0000-0000-0000-00000dad9a01',
   '00000000-0000-0000-0000-00000dad9f02','set9','00000000-0000-0000-0000-00000dad9aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"T","fine_cents":75000}'::jsonb,
   'disputed','XYZ9Z88','Maria Condutora',
   NOW(),'00000000-0000-0000-0000-00000dad9b01',NOW()+INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

-- c01 = submit token for e01 (file) · c02 = submit token for e02 (text).
INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, token, created_by_user_id, expires_at_utc,
   max_access_count, token_scope, max_submissions, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad9c01','00000000-0000-0000-0000-00000dad9a01',
   '00000000-0000-0000-0000-00000dad9e01','00000000-0000-0000-0000-0000dad97001',
   '00000000-0000-0000-0000-00000dad9b01',NOW()+INTERVAL '24 hours',50,'submit',10,NOW()),
  ('00000000-0000-0000-0000-00000dad9c02','00000000-0000-0000-0000-00000dad9a01',
   '00000000-0000-0000-0000-00000dad9e02','00000000-0000-0000-0000-0000dad97002',
   '00000000-0000-0000-0000-00000dad9b01',NOW()+INTERVAL '24 hours',50,'submit',5,NOW())
ON CONFLICT (id) DO NOTHING;

-- ── File defense: create_portal_submission → register_portal_evidence ─────────
DO $$
DECLARE r RECORD; v_att UUID;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad97001','foto.jpg','image/jpeg',2048,repeat('a',64),
    'Justificativa de contestacao com imagem anexa.');
  PERFORM set_config('t.sub_file', r.submission_id::text, true);
  v_att := public.register_portal_evidence(r.submission_id, repeat('a',64),'image/jpeg',2048);
  PERFORM set_config('t.att_file', v_att::text, true);
END $$;

-- ST1: the card STAYS in "Aguardando Evidência" (queue remains disputed).
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id='00000000-0000-0000-0000-00000dad9e01'),
  'disputed', 'ST1: register_portal_evidence keeps the queue disputed (no illegal flip)');

-- ST3: token revoked (one-shot anti-double-submit guard preserved).
SELECT ok(
  (SELECT revoked_at_utc IS NOT NULL FROM public.dispute_portal_tokens
    WHERE id='00000000-0000-0000-0000-00000dad9c01'),
  'ST3: file token revoked after finalize');

-- ALERT1: exactly one operator alert for this queue.
SELECT is(
  (SELECT count(*)::int FROM public.operational_alerts
    WHERE alert_type='DISPUTE_DEFENSE_SUBMITTED'
      AND context->>'queue_entry_id'='00000000-0000-0000-0000-00000dad9e01'),
  1, 'ALERT1: file submission emits exactly one DISPUTE_DEFENSE_SUBMITTED alert');

-- ALERT1b: metadata-only context (no raw testimony) with the right fields.
SELECT ok(
  (SELECT context->>'defense_type'='file'
      AND context->>'filename'='foto.jpg'
      AND context->>'fine_amount_cents'='50000'
      AND context->>'vehicle_plate'='ABC1D23'
      AND context->>'driver_name'='Joao Motorista'
      AND NOT (context ? 'justification_text')
      AND entity_id='ABC1D23'
      AND severity='HIGH'
      AND organization_id='00000000-0000-0000-0000-00000dad9a01'
     FROM public.operational_alerts
    WHERE alert_type='DISPUTE_DEFENSE_SUBMITTED'
      AND context->>'queue_entry_id'='00000000-0000-0000-0000-00000dad9e01'),
  'ALERT1b: file alert carries metadata only (testimony stays in the sealed row)');

-- ST4: register replay is idempotent (same attachment, queue still disputed).
SELECT is(
  public.register_portal_evidence(
    current_setting('t.sub_file')::uuid, repeat('a',64),'image/jpeg',2048),
  current_setting('t.att_file')::uuid,
  'ST4: register replay returns the same attachment (idempotent)');

-- ALERT3: the idempotent replay does NOT duplicate the alert.
SELECT is(
  (SELECT count(*)::int FROM public.operational_alerts
    WHERE alert_type='DISPUTE_DEFENSE_SUBMITTED'
      AND context->>'queue_entry_id'='00000000-0000-0000-0000-00000dad9e01'),
  1, 'ALERT3: replay does not duplicate the alert (ON CONFLICT + early return)');

-- ── Text defense: submit_portal_justification_only ────────────────────────────
DO $$
DECLARE v UUID;
BEGIN
  v := public.submit_portal_justification_only(
    '00000000-0000-0000-0000-0000dad97002',
    'Defesa textual detalhada sem anexo para o teste.');
  PERFORM set_config('t.pjs', v::text, true);
END $$;

-- ST2: text-defense queue STAYS disputed.
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id='00000000-0000-0000-0000-00000dad9e02'),
  'disputed', 'ST2: submit_portal_justification_only keeps the queue disputed');

-- TOKEN-TEXT: text token revoked.
SELECT ok(
  (SELECT revoked_at_utc IS NOT NULL FROM public.dispute_portal_tokens
    WHERE id='00000000-0000-0000-0000-00000dad9c02'),
  'TOKEN-TEXT: text token revoked after submit');

-- ALERT2: exactly one alert for the text queue.
SELECT is(
  (SELECT count(*)::int FROM public.operational_alerts
    WHERE alert_type='DISPUTE_DEFENSE_SUBMITTED'
      AND context->>'queue_entry_id'='00000000-0000-0000-0000-00000dad9e02'),
  1, 'ALERT2: text submission emits exactly one alert');

-- ALERT2b: defense_type='text', no filename.
SELECT ok(
  (SELECT context->>'defense_type'='text'
      AND (context->>'filename') IS NULL
      AND context->>'fine_amount_cents'='75000'
     FROM public.operational_alerts
    WHERE alert_type='DISPUTE_DEFENSE_SUBMITTED'
      AND context->>'queue_entry_id'='00000000-0000-0000-0000-00000dad9e02'),
  'ALERT2b: text alert has defense_type=text and null filename');

-- ZOMBIE: the portal path NEVER mints a pending_peer_review row for this org.
SELECT is(
  (SELECT count(*)::int FROM public.sanction_review_queue
    WHERE organization_id='00000000-0000-0000-0000-00000dad9a01'
      AND status='pending_peer_review'),
  0, 'ZOMBIE: portal submissions never produce an un-confirmable peer-review row');

-- ── CHECK widening (rename-back) ──────────────────────────────────────────────
SELECT ok(
  EXISTS(SELECT 1 FROM pg_constraint
          WHERE conname='valid_alert_type'
            AND conrelid='public.operational_alerts'::regclass),
  'CHK-CANON: constraint keeps its canonical name valid_alert_type after rename-back');

SELECT lives_ok(
  $$ INSERT INTO public.operational_alerts
       (organization_id, entity_id, contract_id, alert_type, severity, triggering_event_id)
     VALUES ('00000000-0000-0000-0000-00000dad9a01','E2','C2',
             'DISPUTE_DEFENSE_SUBMITTED','HIGH','00000000-0000-0000-0000-00000dad9ff1') $$,
  'CHK7: DISPUTE_DEFENSE_SUBMITTED admitted by the widened CHECK');

SELECT throws_ok(
  $$ INSERT INTO public.operational_alerts
       (organization_id, entity_id, contract_id, alert_type, severity, triggering_event_id)
     VALUES ('00000000-0000-0000-0000-00000dad9a01','E3','C3',
             'BOGUS_TYPE','HIGH','00000000-0000-0000-0000-00000dad9ff2') $$,
  '23514', NULL, 'CHK-REJECT: an unknown alert_type is still rejected (CHECK active)');

SELECT * FROM finish();
ROLLBACK;
