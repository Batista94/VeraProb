BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- =============================================================================
-- pgTAP: portal_ledger_types — CHECK widening for Dispute Portal facts (5.3)
-- Migration: 20260814000001_portal_ledger_types.sql
-- Proves the H1-safe widening accepts the 3 new portal fact types under the
-- canonical constraint name, still rejects bogus types, and keeps the legacy
-- vocabulary valid (no regression on pre-10.6 facts).
-- =============================================================================

-- Org seed (FK: sla_audit_ledger_v2.organization_id -> organizations.id).
INSERT INTO public.organizations (id, name, cnpj, created_at)
VALUES (
  'aaaaaaaa-0000-0000-0000-000000000001',
  'Org Ledger Types', '00000000lt0001', NOW()
) ON CONFLICT (id) DO NOTHING;

-- T1: canonical constraint name survived the rename-back (v3 -> chk_ledger_type).
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'chk_ledger_type'
       AND conrelid = 'public.sla_audit_ledger_v2'::regclass
  ),
  'T1: canonical constraint chk_ledger_type present after widening');

-- T2: DISPUTE_PORTAL_TOKEN_GENERATED accepted.
SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, set_id, contract_id, plan_version, payload, occurred_at_utc)
     VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'DISPUTE_PORTAL_TOKEN_GENERATED',
       'set-lt', 'aaaaaaaa-0000-0000-0000-0000000000aa', 0, '{}'::jsonb, NOW()) $$,
  'T2: CHECK accepts DISPUTE_PORTAL_TOKEN_GENERATED');

-- T3: DISPUTE_PORTAL_TOKEN_ACCESSED accepted.
SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, set_id, contract_id, plan_version, payload, occurred_at_utc)
     VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'DISPUTE_PORTAL_TOKEN_ACCESSED',
       'set-lt', 'aaaaaaaa-0000-0000-0000-0000000000aa', 0, '{}'::jsonb, NOW()) $$,
  'T3: CHECK accepts DISPUTE_PORTAL_TOKEN_ACCESSED');

-- T4: DISPUTE_PORTAL_TOKEN_REVOKED accepted.
SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, set_id, contract_id, plan_version, payload, occurred_at_utc)
     VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'DISPUTE_PORTAL_TOKEN_REVOKED',
       'set-lt', 'aaaaaaaa-0000-0000-0000-0000000000aa', 0, '{}'::jsonb, NOW()) $$,
  'T4: CHECK accepts DISPUTE_PORTAL_TOKEN_REVOKED');

-- T5: bogus type still rejected (constraint did not become a no-op).
SELECT throws_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, set_id, contract_id, plan_version, payload, occurred_at_utc)
     VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'NOT_A_REAL_FACT_TYPE',
       'set-lt', 'aaaaaaaa-0000-0000-0000-0000000000aa', 0, '{}'::jsonb, NOW()) $$,
  '23514', NULL,
  'T5: CHECK rejects unknown fact type (check_violation)');

-- T6: legacy fact type still valid (no regression on pre-10.6 vocabulary).
SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, set_id, contract_id, plan_version, payload, occurred_at_utc)
     VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'VERDICT_SEALED',
       'set-lt', 'aaaaaaaa-0000-0000-0000-0000000000aa', 0, '{}'::jsonb, NOW()) $$,
  'T6: CHECK still accepts legacy VERDICT_SEALED (no regression)');

SELECT * FROM finish();
ROLLBACK;
