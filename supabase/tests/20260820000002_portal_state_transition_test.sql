BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(2);

-- =============================================================================
-- pgTAP: portal_state_transition
-- Migration: 20260820000002_portal_state_transition.sql
--
-- This file previously stubbed `SELECT pass()` (CI Block #14 false-green), which
-- let an illegal disputed→pending_peer_review flip ship undetected. It now asserts
-- the CORRECT end-state of the portal submission path (post 20260827000001):
-- the queue stays disputed and the one-shot token is revoked.
-- Full alert + idempotency matrix lives in 20260827000001_*_test.sql.
-- =============================================================================

INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000dad5a01','Org5','Org5 SA','00000000dad5a1',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'o5@test.com',
   'EXT5','LOGISTICS',ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, vehicle_plate, operator_name, disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-00000dad5e01','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5f01','set5','00000000-0000-0000-0000-00000dad5aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D","fine_cents":50000}'::jsonb,
   'disputed','PLA5T01','Operador Cinco',
   NOW(),'00000000-0000-0000-0000-00000dad5b01',NOW()+INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, token, created_by_user_id, expires_at_utc,
   max_access_count, token_scope, max_submissions, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad5c01','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5e01','00000000-0000-0000-0000-0000dad57001',
   '00000000-0000-0000-0000-00000dad5b01',NOW()+INTERVAL '24 hours',50,'submit',10,NOW())
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad57001','f.jpg','image/jpeg',2048,repeat('a',64),
    'Justificativa de contestacao para teste de transicao.');
  PERFORM public.register_portal_evidence(r.submission_id, repeat('a',64),'image/jpeg',2048);
END $$;

SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id='00000000-0000-0000-0000-00000dad5e01'),
  'disputed', 'queue stays disputed after portal finalize (no illegal flip)');

SELECT ok(
  (SELECT revoked_at_utc IS NOT NULL FROM public.dispute_portal_tokens
    WHERE id='00000000-0000-0000-0000-00000dad5c01'),
  'one-shot token revoked after portal finalize');

SELECT * FROM finish();
ROLLBACK;
