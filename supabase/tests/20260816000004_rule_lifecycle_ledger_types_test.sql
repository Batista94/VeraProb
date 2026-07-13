-- =============================================================================
-- Test: Sprint B — Rule Lifecycle Ledger Types (chk_ledger_type widening)
-- Covers: nome canonico preservado pos-widening (lição: testes assert nome),
--         4 novos tipos aceitos, tipo invalido rejeitado (CHECK ativo).
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(7);

-- 1. Nome canonico preservado apos widening H1 (ADD _v4 -> RENAME chk_ledger_type)
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_type ty
    JOIN pg_namespace n ON n.oid = ty.typnamespace
    WHERE n.nspname = 'public' AND ty.typname = 'ledger_event_type'
  ),
  'ledger_event_type enum presente (substitui chk_ledger_type)'
);

-- 2. Constraint intermediaria _v4 nao sobrou
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_ledger_type_v4'
      AND conrelid = 'public.sla_audit_ledger_v2'::regclass
  ),
  'constraint intermediaria chk_ledger_type_v4 removida (rename concluido)'
);

-- Seed org para inserts de fato
INSERT INTO public.organizations (id, name, status)
VALUES ('cccc0000-0000-4000-8000-00000000000c', 'Org Ledger Types', 'ACTIVE')
ON CONFLICT DO NOTHING;

-- 3-6. Novos tipos Sprint B aceitos pelo CHECK
SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, operator_id, set_id, plan_version, payload, occurred_at_utc)
     VALUES ('cccc0000-0000-4000-8000-00000000000c', 'RULE_SCHEDULED',
             'TEST', 'rule-lifecycle-test', 0, '{}', now()) $$,
  'tipo RULE_SCHEDULED aceito'
);

SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, operator_id, set_id, plan_version, payload, occurred_at_utc)
     VALUES ('cccc0000-0000-4000-8000-00000000000c', 'RULE_ACTIVATED',
             'TEST', 'rule-lifecycle-test', 0, '{}', now()) $$,
  'tipo RULE_ACTIVATED aceito'
);

SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, operator_id, set_id, plan_version, payload, occurred_at_utc)
     VALUES ('cccc0000-0000-4000-8000-00000000000c', 'RULE_RETIRED',
             'TEST', 'rule-lifecycle-test', 0, '{}', now()) $$,
  'tipo RULE_RETIRED aceito'
);

SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, operator_id, set_id, plan_version, payload, occurred_at_utc)
     VALUES ('cccc0000-0000-4000-8000-00000000000c', 'CONTRACT_FINANCIAL_TERMS_AMENDED',
             'TEST', 'rule-lifecycle-test', 0, '{}', now()) $$,
  'tipo CONTRACT_FINANCIAL_TERMS_AMENDED aceito'
);

-- 7. Tipo desconhecido continua bloqueado (CHECK valida e ativo)
SELECT throws_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, operator_id, set_id, plan_version, payload, occurred_at_utc)
     VALUES ('cccc0000-0000-4000-8000-00000000000c', 'TOTALLY_BOGUS_TYPE',
             'TEST', 'rule-lifecycle-test', 0, '{}', now()) $$,
  '22P02', NULL,
  'tipo fora da taxonomia -> CHECK rejeita'
);

SELECT * FROM finish();
ROLLBACK;
