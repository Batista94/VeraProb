BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

-- =============================================================================
-- pgTAP: defense_submitted_at
-- Migration under test: 20260828000001_defense_submitted_at.sql
--
-- Proves the write-once defense signal is stamped on the queue row by both
-- portal submission paths WITHOUT a status flip, is idempotent on replay, and is
-- sealed write-once by prevent_srq_immutable_mutation.
-- Local pgTAP lacks the 4-arg schema-qualified col_is_nullable overload — schema
-- assertions go through information_schema + ok().
-- Seed UUIDs use only hex chars (d/a/8 + digits).
-- =============================================================================

-- ── Schema ──────────────────────────────────────────────────────────────────
SELECT ok(
  EXISTS(
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='sanction_review_queue'
       AND column_name='defense_submitted_at'
       AND data_type='timestamp with time zone'),
  'COL_EXISTS: defense_submitted_at is TIMESTAMPTZ on sanction_review_queue');

SELECT ok(
  EXISTS(
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='sanction_review_queue'
       AND column_name='defense_submitted_at'
       AND is_nullable='YES' AND column_default IS NULL),
  'COL_NULLABLE: defense_submitted_at is nullable with NO default (INV-6)');

-- ── Seeds ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000dad8a01','Org8','Org8 SA','00000000dad8a1',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'o8@test.com',
   'EXT8','LOGISTICS',ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- e01 = file-defense queue · e02 = text-defense queue (both disputed).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, vehicle_plate, operator_name, disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8f01','set8','00000000-0000-0000-0000-00000dad8aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D","fine_cents":50000}'::jsonb,
   'disputed','ABC1D23','Joao Motorista',
   NOW(),'00000000-0000-0000-0000-00000dad8b01',NOW()+INTERVAL '5 days'),
  ('00000000-0000-0000-0000-00000dad8e02','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8f02','set8','00000000-0000-0000-0000-00000dad8aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"T","fine_cents":75000}'::jsonb,
   'disputed','XYZ9Z88','Maria Condutora',
   NOW(),'00000000-0000-0000-0000-00000dad8b01',NOW()+INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

-- c01 = submit token for e01 (file) · c02 = submit token for e02 (text).
INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, token, created_by_user_id, expires_at_utc,
   max_access_count, token_scope, max_submissions, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad8c01','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-0000dad87001',
   '00000000-0000-0000-0000-00000dad8b01',NOW()+INTERVAL '24 hours',50,'submit',10,NOW()),
  ('00000000-0000-0000-0000-00000dad8c02','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e02','00000000-0000-0000-0000-0000dad87002',
   '00000000-0000-0000-0000-00000dad8b01',NOW()+INTERVAL '24 hours',50,'submit',5,NOW())
ON CONFLICT (id) DO NOTHING;

-- ── File defense: create_portal_submission → register_portal_evidence ─────────
DO $$
DECLARE r RECORD; v_att UUID;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87001','foto.jpg','image/jpeg',2048,repeat('a',64),
    'Justificativa de contestacao com imagem anexa.');
  PERFORM set_config('t.sub_file', r.submission_id::text, true);
  v_att := public.register_portal_evidence(r.submission_id, repeat('a',64),'image/jpeg',2048);
  PERFORM set_config('t.att_file', v_att::text, true);
  -- Snapshot the first stamp for the replay-no-advance assertion.
  PERFORM set_config('t.stamp1',
    (SELECT defense_submitted_at::text FROM public.sanction_review_queue
      WHERE id='00000000-0000-0000-0000-00000dad8e01'), true);
END $$;

SELECT ok(
  (SELECT defense_submitted_at IS NOT NULL FROM public.sanction_review_queue
    WHERE id='00000000-0000-0000-0000-00000dad8e01'),
  'REGISTER_SETS: register_portal_evidence stamps defense_submitted_at');

SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id='00000000-0000-0000-0000-00000dad8e01'),
  'disputed', 'REGISTER_KEEPS_DISPUTED: queue stays disputed (no flip, anti-regression)');

-- Replay finalize; the IS NULL guard must leave the first stamp untouched.
DO $$
BEGIN
  PERFORM public.register_portal_evidence(
    current_setting('t.sub_file')::uuid, repeat('a',64),'image/jpeg',2048);
END $$;

SELECT is(
  (SELECT defense_submitted_at::text FROM public.sanction_review_queue
    WHERE id='00000000-0000-0000-0000-00000dad8e01'),
  current_setting('t.stamp1'),
  'REGISTER_REPLAY_NO_ADVANCE: replay does not advance the first-submission stamp');

-- ── Text defense: submit_portal_justification_only ────────────────────────────
DO $$
BEGIN
  PERFORM public.submit_portal_justification_only(
    '00000000-0000-0000-0000-0000dad87002',
    'Defesa textual detalhada sem anexo para o teste.');
END $$;

SELECT ok(
  (SELECT defense_submitted_at IS NOT NULL FROM public.sanction_review_queue
    WHERE id='00000000-0000-0000-0000-00000dad8e02'),
  'JUSTIFY_SETS: submit_portal_justification_only stamps defense_submitted_at');

SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id='00000000-0000-0000-0000-00000dad8e02'),
  'disputed', 'JUSTIFY_KEEPS_DISPUTED: queue stays disputed after text submit');

-- ── Write-once seal: clearing/altering a set stamp is rejected ────────────────
SELECT throws_ok(
  $$ UPDATE public.sanction_review_queue
        SET defense_submitted_at = NOW() + INTERVAL '1 hour'
      WHERE id='00000000-0000-0000-0000-00000dad8e01' $$,
  '23001', NULL,
  'WRITE_ONCE_BLOCKS: altering a set defense_submitted_at throws restrict_violation (INV-18)');

SELECT * FROM finish();
ROLLBACK;
