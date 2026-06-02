BEGIN;
SELECT plan(29);

-- ── 1. Verify always-true policies are dropped ───────────────────────────────
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'idempotency_keys'
      AND policyname = 'idempotency_keys_service_all'
  ),
  'idempotency_keys_service_all has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'telegram_chat_bindings'
      AND policyname = 'tcb_service_all'
  ),
  'tcb_service_all has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'telegram_user_consents'
      AND policyname = 'tuc_select_service'
  ),
  'tuc_select_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'telegram_binding_tokens'
      AND policyname = 'tbt_update_service'
  ),
  'tbt_update_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'justification_recomputation_signals'
      AND policyname = 'jrs_update_service'
  ),
  'jrs_update_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'justification_submission_tokens'
      AND policyname = 'jst_update_service'
  ),
  'jst_update_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'justification_audit_logs'
      AND policyname = 'jal_insert_service'
  ),
  'jal_insert_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'justification_recomputation_signals'
      AND policyname = 'jrs_insert_service'
  ),
  'jrs_insert_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'justification_submission_tokens'
      AND policyname = 'jst_insert_service'
  ),
  'jst_insert_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'sanction_escalation_log'
      AND policyname = 'sel_insert_service'
  ),
  'sel_insert_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'telegram_evidence_categories'
      AND policyname = 'tec_insert_service'
  ),
  'tec_insert_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'telegram_evidence_metadata'
      AND policyname = 'tem_insert_service'
  ),
  'tem_insert_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'telegram_user_consents'
      AND policyname = 'tuc_insert_service'
  ),
  'tuc_insert_service has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'contractual_financial_snapshot'
      AND policyname = 'Snapshot Read'
  ),
  'Snapshot Read always-true policy has been dropped'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'contractual_financial_snapshot'
      AND policyname = 'Snapshot Insert'
  ),
  'Snapshot Insert always-true policy has been dropped'
);

-- ── 2. Verify restrictive deny-all policies are present ───────────────────────
SELECT is(
  (SELECT permissive::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'telegram_pending_links' AND policyname = 'deny-all authenticated: telegram_pending_links'),
  'RESTRICTIVE',
  'telegram_pending_links should have RESTRICTIVE deny-all policy'
);

SELECT is(
  (SELECT permissive::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'telegram_user_consents' AND policyname = 'deny-all authenticated: telegram_user_consents'),
  'RESTRICTIVE',
  'telegram_user_consents should have RESTRICTIVE deny-all policy'
);

-- ── 3. Verify new INSERT policies exist for authenticated role ─────────────────
SELECT is(
  (SELECT cmd::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'sanction_review_queue' AND policyname = 'srq_insert_authenticated'),
  'INSERT',
  'sanction_review_queue has srq_insert_authenticated policy command'
);
SELECT is(
  (SELECT roles::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'sanction_review_queue' AND policyname = 'srq_insert_authenticated'),
  '{authenticated}',
  'sanction_review_queue has srq_insert_authenticated policy roles'
);

SELECT is(
  (SELECT cmd::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'shadow_verdicts' AND policyname = 'sv_insert_authenticated'),
  'INSERT',
  'shadow_verdicts has sv_insert_authenticated policy command'
);
SELECT is(
  (SELECT roles::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'shadow_verdicts' AND policyname = 'sv_insert_authenticated'),
  '{authenticated}',
  'shadow_verdicts has sv_insert_authenticated policy roles'
);

SELECT is(
  (SELECT cmd::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'telegram_evidence_links' AND policyname = 'tel_insert_authenticated'),
  'INSERT',
  'telegram_evidence_links has tel_insert_authenticated policy command'
);
SELECT is(
  (SELECT roles::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'telegram_evidence_links' AND policyname = 'tel_insert_authenticated'),
  '{authenticated}',
  'telegram_evidence_links has tel_insert_authenticated policy roles'
);

SELECT is(
  (SELECT cmd::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'telegram_evidence_uploads' AND policyname = 'teu_insert_authenticated'),
  'INSERT',
  'telegram_evidence_uploads has teu_insert_authenticated policy command'
);
SELECT is(
  (SELECT roles::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'telegram_evidence_uploads' AND policyname = 'teu_insert_authenticated'),
  '{authenticated}',
  'telegram_evidence_uploads has teu_insert_authenticated policy roles'
);

-- ── 4. Behavioral testing of tenant isolation on INSERT ───────────────────────

-- Grant permissions for testing
GRANT SELECT, INSERT ON public.sanction_review_queue TO authenticated;
GRANT SELECT, INSERT ON public.shadow_verdicts TO authenticated;

-- Switch role and set JWT claims
SET LOCAL ROLE authenticated;

-- A. sanction_review_queue check
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000002","organization_id":"a0000000-0000-0000-0000-00000000000a","role":"admin"}';

-- Insert with own org_id should succeed
SELECT lives_ok(
  $$ INSERT INTO public.sanction_review_queue (
       organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence
     ) VALUES (
       'a0000000-0000-0000-0000-00000000000a',
       gen_random_uuid(),
       'set_123',
       'contract_123',
       '{}'::jsonb
     ) $$,
  'Inserting with own org_id into sanction_review_queue succeeds'
);

-- Insert with foreign org_id should be blocked by RLS WITH CHECK
SELECT throws_ok(
  $$ INSERT INTO public.sanction_review_queue (
       organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence
     ) VALUES (
       'b0000000-0000-0000-0000-00000000000b',
       gen_random_uuid(),
       'set_123',
       'contract_123',
       '{}'::jsonb
     ) $$,
  'new row violates row-level security policy for table "sanction_review_queue"',
  'Cross-tenant insert into sanction_review_queue is blocked by RLS'
);

-- B. shadow_verdicts check
SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"a0000000-0000-0000-0000-00000000000a"}}';

-- Insert with own org_id should succeed
SELECT lives_ok(
  $$ INSERT INTO public.shadow_verdicts (
       organization_id, set_id, contract_id, engine_verdict, engine_verdict_at_utc, engine_version, verdict_evidence, traceability_hash
     ) VALUES (
       'a0000000-0000-0000-0000-00000000000a',
       'set_456',
       'contract_456',
       'executed',
       NOW(),
       '1.0.0',
       '{}'::jsonb,
       'hash123'
     ) $$,
  'Inserting with own org_id into shadow_verdicts succeeds'
);

-- Insert with foreign org_id should be blocked by RLS WITH CHECK
SELECT throws_ok(
  $$ INSERT INTO public.shadow_verdicts (
       organization_id, set_id, contract_id, engine_verdict, engine_verdict_at_utc, engine_version, verdict_evidence, traceability_hash
     ) VALUES (
       'b0000000-0000-0000-0000-00000000000b',
       'set_789',
       'contract_789',
       'executed',
       NOW(),
       '1.0.0',
       '{}'::jsonb,
       'hash456'
     ) $$,
  'new row violates row-level security policy for table "shadow_verdicts"',
  'Cross-tenant insert into shadow_verdicts is blocked by RLS'
);

SELECT * FROM finish();
ROLLBACK;
