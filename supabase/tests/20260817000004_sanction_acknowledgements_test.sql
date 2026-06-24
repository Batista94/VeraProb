BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

-- =============================================================================
-- pgTAP: sanction_acknowledgements — Sprint A M4
-- Covers: table shape, method/hash consistency CHECKs, append-only, RLS/grants,
-- chk_srq_status widening ('acknowledged'), and the terminal-status seal.
-- =============================================================================

-- ── Seeds (as postgres) ──────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000dad4a01', 'Org Ack', 'Org Ack SA', '00000000dad4a1',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'ack@test.com', 'EXT_ACK', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-00000dad4e01', '00000000-0000-0000-0000-00000dad4a01',
   '00000000-0000-0000-0000-00000dad4f01', 'set-ack',
   '00000000-0000-0000-0000-00000dad4aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"Applied","fine_cents":50000}'::jsonb,
   'applied'),
  ('00000000-0000-0000-0000-00000dad4e02', '00000000-0000-0000-0000-00000dad4a01',
   '00000000-0000-0000-0000-00000dad4f02', 'set-ack',
   '00000000-0000-0000-0000-00000dad4aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"Applied2"}'::jsonb,
   'applied')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, created_by_user_id,
   expires_at_utc, max_access_count, token_scope, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad4c01', '00000000-0000-0000-0000-00000dad4a01',
   '00000000-0000-0000-0000-00000dad4e01', '00000000-0000-0000-0000-00000dad4b01',
   NOW() + INTERVAL '24 hours', 5, 'read', NOW())
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- STRUCTURE
-- =============================================================================

SELECT has_table('public', 'sanction_acknowledgements',
  'S1: sanction_acknowledgements table exists');

SELECT has_column('public', 'sanction_acknowledgements', 'snapshot_hash_acknowledged',
  'S2: snapshot_hash_acknowledged column exists');

-- S3: chk_srq_status now admits 'acknowledged'
SELECT ok(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conname = 'chk_srq_status') LIKE '%acknowledged%',
  'S3: chk_srq_status admits acknowledged (canonical name preserved)');

-- =============================================================================
-- METHOD / HASH CONSISTENCY CHECKS
-- =============================================================================

-- C1: PORTAL_TOKEN without snapshot hash → 23514
SELECT throws_ok(
  $$ INSERT INTO public.sanction_acknowledgements
       (organization_id, queue_entry_id, acknowledgement_method, acknowledged_via_token_id)
     VALUES ('00000000-0000-0000-0000-00000dad4a01','00000000-0000-0000-0000-00000dad4e01',
             'PORTAL_TOKEN','00000000-0000-0000-0000-00000dad4c01') $$,
  '23514', NULL, 'C1: PORTAL_TOKEN without snapshot hash rejected');

-- C2: INTERNAL_RECORD without acknowledged_by_user_id → 23514
SELECT throws_ok(
  $$ INSERT INTO public.sanction_acknowledgements
       (organization_id, queue_entry_id, acknowledgement_method)
     VALUES ('00000000-0000-0000-0000-00000dad4a01','00000000-0000-0000-0000-00000dad4e01',
             'INTERNAL_RECORD') $$,
  '23514', NULL, 'C2: INTERNAL_RECORD without user rejected');

-- C3: invalid method → 23514
SELECT throws_ok(
  $$ INSERT INTO public.sanction_acknowledgements
       (organization_id, queue_entry_id, acknowledgement_method, acknowledged_by_user_id)
     VALUES ('00000000-0000-0000-0000-00000dad4a01','00000000-0000-0000-0000-00000dad4e01',
             'BOGUS','00000000-0000-0000-0000-00000dad4b01') $$,
  '23514', NULL, 'C3: invalid acknowledgement_method rejected');

-- C4: malformed snapshot hash → 23514
SELECT throws_ok(
  $$ INSERT INTO public.sanction_acknowledgements
       (organization_id, queue_entry_id, snapshot_hash_acknowledged,
        acknowledgement_method, acknowledged_via_token_id)
     VALUES ('00000000-0000-0000-0000-00000dad4a01','00000000-0000-0000-0000-00000dad4e01',
             'NOTAHASH','PORTAL_TOKEN','00000000-0000-0000-0000-00000dad4c01') $$,
  '23514', NULL, 'C4: malformed snapshot hash rejected');

-- =============================================================================
-- HAPPY PATHS
-- =============================================================================

-- HP1: valid PORTAL_TOKEN acknowledgement
SELECT lives_ok(
  format($$ INSERT INTO public.sanction_acknowledgements
       (id, organization_id, queue_entry_id, snapshot_hash_acknowledged,
        acknowledgement_method, acknowledged_via_token_id)
     VALUES ('00000000-0000-0000-0000-00000dad4501','00000000-0000-0000-0000-00000dad4a01',
             '00000000-0000-0000-0000-00000dad4e01', %L,
             'PORTAL_TOKEN','00000000-0000-0000-0000-00000dad4c01') $$, repeat('a',64)),
  'HP1: valid PORTAL_TOKEN acknowledgement inserts');

-- HP2: valid INTERNAL_RECORD acknowledgement
SELECT lives_ok(
  $$ INSERT INTO public.sanction_acknowledgements
       (id, organization_id, queue_entry_id, acknowledgement_method, acknowledged_by_user_id, notes)
     VALUES ('00000000-0000-0000-0000-00000dad4502','00000000-0000-0000-0000-00000dad4a01',
             '00000000-0000-0000-0000-00000dad4e02','INTERNAL_RECORD',
             '00000000-0000-0000-0000-00000dad4b01','phone, 2026-06-13') $$,
  'HP2: valid INTERNAL_RECORD acknowledgement inserts');

-- =============================================================================
-- APPEND-ONLY
-- =============================================================================

-- IM: UPDATE blocked
SELECT throws_ok(
  $$ UPDATE public.sanction_acknowledgements SET notes = 'x'
      WHERE id = '00000000-0000-0000-0000-00000dad4501' $$,
  '23001', NULL, 'IM: UPDATE blocked (append-only INV-3)');

-- DEL: DELETE blocked
SELECT throws_ok(
  $$ DELETE FROM public.sanction_acknowledgements
      WHERE id = '00000000-0000-0000-0000-00000dad4502' $$,
  '23001', NULL, 'DEL: DELETE blocked (append-only INV-3)');

-- =============================================================================
-- GRANTS / RLS
-- =============================================================================

SELECT ok(
  has_table_privilege('authenticated', 'public.sanction_acknowledgements', 'SELECT'),
  'G1: authenticated can SELECT (org-scoped via RLS)');

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.sanction_acknowledgements', 'INSERT'),
  'G2: authenticated cannot INSERT (RPC-only)');

-- =============================================================================
-- TERMINAL STATUS SEAL
-- =============================================================================

-- TS1: applied → acknowledged is a legal transition
SELECT lives_ok(
  $$ UPDATE public.sanction_review_queue SET status = 'acknowledged'
      WHERE id = '00000000-0000-0000-0000-00000dad4e01' $$,
  'TS1: applied → acknowledged allowed');

-- TS2: acknowledged → anything blocked (terminal)
SELECT throws_ok(
  $$ UPDATE public.sanction_review_queue SET status = 'rejected'
      WHERE id = '00000000-0000-0000-0000-00000dad4e01' $$,
  '23001', NULL, 'TS2: acknowledged is terminal — transition blocked (INV-3)');

SELECT * FROM finish();
ROLLBACK;
