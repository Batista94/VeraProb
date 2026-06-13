-- =============================================================================
-- Test: Sprint B — Rule Versioning RPCs (behavioral, failure-first)
-- Covers: anti-backdating (INV-15), schedule/activate/retire lifecycle,
--         ledger facts (INV-3/21), cross-org isolation with
--         validate-before-write (INV-22/26), RBAC, financial amendments (INV-4).
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(35);

-- ── Seed (as postgres: bypass RLS) ───────────────────────────────────────────
INSERT INTO public.organizations (id, name, status) VALUES
  ('aaaa0000-0000-4000-8000-00000000000a', 'Org A Rule RPCs', 'ACTIVE'),
  ('bbbb0000-0000-4000-8000-00000000000b', 'Org B Rule RPCs', 'ACTIVE')
ON CONFLICT DO NOTHING;

INSERT INTO public.contracts
  (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc, status)
VALUES
  ('aaaa0000-0000-4000-8000-0000000000ca', 'aaaa0000-0000-4000-8000-00000000000a',
   'Contract A', 'Carrier A', now() - INTERVAL '1 day', now() + INTERVAL '1 year', 'active')
ON CONFLICT (id) DO NOTHING;

-- ── 1-5. Signatures ──────────────────────────────────────────────────────────
SELECT has_function('public', 'update_contractual_rule', ARRAY['uuid', 'uuid', 'sla_rule_type', 'jsonb', 'integer', 'timestamp with time zone']);
SELECT has_function('public', 'schedule_contractual_rule', ARRAY['uuid', 'uuid', 'sla_rule_type', 'jsonb', 'integer', 'timestamp with time zone']);
SELECT has_function('public', 'activate_scheduled_rule', ARRAY['uuid']);
SELECT has_function('public', 'retire_contractual_rule', ARRAY['uuid']);
SELECT has_function('public', 'amend_contract_financial_terms', ARRAY['uuid', 'bigint', 'integer', 'timestamp with time zone', 'text']);

-- ── Org A TENANT_ADMIN context ───────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"aaaa0000-0000-4000-8000-0000000000ad","organization_id":"aaaa0000-0000-4000-8000-00000000000a","app_metadata":{"org_id":"aaaa0000-0000-4000-8000-00000000000a","role":"TENANT_ADMIN"}}';

-- ── 6-7. update_contractual_rule: happy path (current rule v1) ───────────────
CREATE TEMP TABLE tt_upd AS
SELECT public.update_contractual_rule(
  'aaaa0000-0000-4000-8000-0000000000ca', NULL,
  'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 15}', 1, now()
) AS id;

SELECT ok((SELECT id FROM tt_upd) IS NOT NULL, 'update happy path retorna UUID da nova versao');

RESET ROLE;
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.contract_rule_versions
    WHERE id = (SELECT id FROM tt_upd)
      AND is_scheduled = false AND active_to_utc IS NULL
  ),
  'regra criada como CORRENTE (is_scheduled=false, aberta)'
);

-- ── 8-9. update_contractual_rule: anti-backdating + anti-future ──────────────
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ SELECT public.update_contractual_rule(
       'aaaa0000-0000-4000-8000-0000000000ca',
       (SELECT id FROM tt_upd),
       'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 10}', 1,
       now() - INTERVAL '30 days') $$,
  'P0001', 'Anti-backdating violation: p_now_utc is too far in the past',
  'update com effective 30 dias no passado -> bloqueado (INV-15)'
);

SELECT throws_ok(
  $$ SELECT public.update_contractual_rule(
       'aaaa0000-0000-4000-8000-0000000000ca',
       (SELECT id FROM tt_upd),
       'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 10}', 1,
       now() + INTERVAL '1 day') $$,
  'P0001', 'Future effective dates must use schedule_contractual_rule',
  'update com effective futuro -> deve usar schedule (semantica corrente)'
);

-- ── 10-12. schedule_contractual_rule: happy path + ledger fact ───────────────
CREATE TEMP TABLE tt_sch AS
SELECT public.schedule_contractual_rule(
  'aaaa0000-0000-4000-8000-0000000000ca',
  (SELECT id FROM tt_upd),
  'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 20}', 1,
  now() + INTERVAL '7 days'
) AS id;

SELECT ok((SELECT id FROM tt_sch) IS NOT NULL, 'schedule happy path retorna UUID');

RESET ROLE;
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.contract_rule_versions
    WHERE id = (SELECT id FROM tt_sch)
      AND is_scheduled = true AND active_to_utc IS NULL
  ),
  'regra agendada criada (is_scheduled=true) sem fechar a corrente'
);

SELECT is(
  (SELECT count(*) FROM public.sla_audit_ledger_v2
   WHERE organization_id = 'aaaa0000-0000-4000-8000-00000000000a'
     AND type = 'RULE_SCHEDULED'
     AND contract_id = 'aaaa0000-0000-4000-8000-0000000000ca'
     AND (payload ->> 'rule_id')::uuid = (SELECT id FROM tt_sch)),
  1::bigint,
  'fato RULE_SCHEDULED selado no ledger com set_id/contract_id (INV-3/21)'
);

-- ── 13-14. schedule: passado proibido + agendada duplicada por tipo ───────────
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ SELECT public.schedule_contractual_rule(
       'aaaa0000-0000-4000-8000-0000000000ca', NULL,
       'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 5}', 1,
       now() - INTERVAL '1 hour') $$,
  'P0001', 'Scheduled rules must be strictly in the future',
  'schedule no passado -> bloqueado'
);

SELECT throws_ok(
  $$ SELECT public.schedule_contractual_rule(
       'aaaa0000-0000-4000-8000-0000000000ca', NULL,
       'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 25}', 1,
       now() + INTERVAL '14 days') $$,
  '23505', NULL,
  '2a agendada do mesmo tipo -> idx_unique_scheduled_rule viola'
);

-- ── 15-19. activate_scheduled_rule: promove + fecha corrente + idempotente ───
SELECT lives_ok(
  $$ SELECT public.activate_scheduled_rule((SELECT id FROM tt_sch)) $$,
  'activate da agendada executa'
);

RESET ROLE;
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.contract_rule_versions
    WHERE id = (SELECT id FROM tt_sch)
      AND is_scheduled = false AND active_to_utc IS NULL
  ),
  'agendada promovida a CORRENTE'
);

SELECT ok(
  (SELECT active_to_utc IS NOT NULL FROM public.contract_rule_versions
   WHERE id = (SELECT id FROM tt_upd)),
  'corrente anterior fechada na ativacao (historico preservado, INV-3)'
);

SELECT is(
  (SELECT count(*) FROM public.sla_audit_ledger_v2
   WHERE organization_id = 'aaaa0000-0000-4000-8000-00000000000a'
     AND type = 'RULE_ACTIVATED'
     AND (payload ->> 'rule_id')::uuid = (SELECT id FROM tt_sch)),
  1::bigint,
  'fato RULE_ACTIVATED selado no ledger'
);

SET LOCAL ROLE authenticated;
SELECT lives_ok(
  $$ SELECT public.activate_scheduled_rule((SELECT id FROM tt_sch)) $$,
  'activate repetido -> idempotente (sucesso silencioso)'
);

-- ── 20-23. retire_contractual_rule: sela sem sucessor + fato + re-retire ─────
SELECT lives_ok(
  $$ SELECT public.retire_contractual_rule((SELECT id FROM tt_sch)) $$,
  'retire da regra corrente executa'
);

RESET ROLE;
SELECT ok(
  (SELECT active_to_utc IS NOT NULL FROM public.contract_rule_versions
   WHERE id = (SELECT id FROM tt_sch)),
  'retire sela active_to_utc SEM sucessor'
);

SELECT is(
  (SELECT count(*) FROM public.sla_audit_ledger_v2
   WHERE organization_id = 'aaaa0000-0000-4000-8000-00000000000a'
     AND type = 'RULE_RETIRED'
     AND (payload ->> 'rule_id')::uuid = (SELECT id FROM tt_sch)),
  1::bigint,
  'fato RULE_RETIRED selado no ledger (sinal legal de remocao)'
);

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ SELECT public.retire_contractual_rule((SELECT id FROM tt_sch)) $$,
  'P0001', 'Rule not found, already closed, or unauthorized',
  're-retire de regra ja fechada -> bloqueado'
);

-- ── 24-27. Cross-org (INV-22/26): validate-before-write ──────────────────────
CREATE TEMP TABLE tt_gap AS
SELECT public.update_contractual_rule(
  'aaaa0000-0000-4000-8000-0000000000ca', NULL,
  'MAX_EVIDENCE_GAP', '{"max_gap_seconds": 300}', 2, now()
) AS id;

SELECT ok((SELECT id FROM tt_gap) IS NOT NULL, 'regra GAP corrente criada na Org A');

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"bbbb0000-0000-4000-8000-0000000000bd","organization_id":"bbbb0000-0000-4000-8000-00000000000b","app_metadata":{"org_id":"bbbb0000-0000-4000-8000-00000000000b","role":"TENANT_ADMIN"}}';

SELECT throws_ok(
  $$ SELECT public.retire_contractual_rule((SELECT id FROM tt_gap)) $$,
  'P0001', 'Rule not found, already closed, or unauthorized',
  'Org B retire em regra da Org A -> rejeitado (anti-oracle: mesma msg de not-found)'
);

RESET ROLE;
SELECT ok(
  (SELECT active_to_utc IS NULL FROM public.contract_rule_versions
   WHERE id = (SELECT id FROM tt_gap)),
  'regra da Org A INTACTA apos tentativa cross-org (validate-before-write)'
);

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ SELECT public.schedule_contractual_rule(
       'aaaa0000-0000-4000-8000-0000000000ca', NULL,
       'NO_SHOW_PENALTY', '{"penalty_amount_cents": 50000}', 3,
       now() + INTERVAL '1 day') $$,
  'P0001', NULL,
  'Org B schedule em contrato da Org A -> rejeitado'
);

-- ── 28. RBAC: OPERATOR bloqueado ─────────────────────────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"aaaa0000-0000-4000-8000-0000000000ad","organization_id":"aaaa0000-0000-4000-8000-00000000000a","app_metadata":{"org_id":"aaaa0000-0000-4000-8000-00000000000a","role":"OPERATOR"}}';

SELECT throws_ok(
  $$ SELECT public.update_contractual_rule(
       'aaaa0000-0000-4000-8000-0000000000ca', NULL,
       'NO_SHOW_PENALTY', '{"penalty_amount_cents": 1000}', 3, now()) $$,
  'P0001', 'Unauthorized: TENANT_ADMIN role required',
  'OPERATOR em RPC de regra -> bloqueado (RBAC server-side)'
);

-- ── 29-32. amend_contract_financial_terms: happy + denorm + ledger ───────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"aaaa0000-0000-4000-8000-0000000000ad","organization_id":"aaaa0000-0000-4000-8000-00000000000a","app_metadata":{"org_id":"aaaa0000-0000-4000-8000-00000000000a","role":"TENANT_ADMIN"}}';

CREATE TEMP TABLE tt_amd AS
SELECT public.amend_contract_financial_terms(
  'aaaa0000-0000-4000-8000-0000000000ca',
  5000000, 15000, now(), 'Renegociacao anual'
) AS id;

SELECT ok((SELECT id FROM tt_amd) IS NOT NULL, 'amend happy path retorna UUID');

RESET ROLE;
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.contract_financial_amendments
    WHERE id = (SELECT id FROM tt_amd)
      AND penalty_multiplier_bps = 15000
      AND financial_ceiling_cents = 5000000
      AND amended_by_user_id = 'aaaa0000-0000-4000-8000-0000000000ad'
  ),
  'amendment registrado append-only com bps INT (INV-4) e autor selado'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.contracts
    WHERE id = 'aaaa0000-0000-4000-8000-0000000000ca'
      AND financial_ceiling_cents = 5000000
      AND abs(penalty_multiplier - 1.5) < 1e-9
  ),
  'denormalizacao em contracts sincronizada (ceiling + multiplier 15000bps=1.5)'
);

SELECT is(
  (SELECT count(*) FROM public.sla_audit_ledger_v2
   WHERE organization_id = 'aaaa0000-0000-4000-8000-00000000000a'
     AND type = 'CONTRACT_FINANCIAL_TERMS_AMENDED'
     AND (payload ->> 'amendment_id')::uuid = (SELECT id FROM tt_amd)),
  1::bigint,
  'fato CONTRACT_FINANCIAL_TERMS_AMENDED selado no ledger'
);

-- ── 33-35. amend: backdate, bps invalido, cross-org ──────────────────────────
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ SELECT public.amend_contract_financial_terms(
       'aaaa0000-0000-4000-8000-0000000000ca',
       NULL, 12000, now() - INTERVAL '2 days', 'fraude retroativa') $$,
  'P0001', 'Anti-backdating violation: p_effective_at_utc is too far in the past',
  'amend retroativo -> bloqueado (INV-15: relatorio passado intocavel)'
);

SELECT throws_ok(
  $$ SELECT public.amend_contract_financial_terms(
       'aaaa0000-0000-4000-8000-0000000000ca',
       NULL, 0, now(), 'bps zero') $$,
  'P0001', 'penalty_multiplier_bps must be a positive integer (INV-4)',
  'amend com bps=0 -> bloqueado'
);

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"bbbb0000-0000-4000-8000-0000000000bd","organization_id":"bbbb0000-0000-4000-8000-00000000000b","app_metadata":{"org_id":"bbbb0000-0000-4000-8000-00000000000b","role":"TENANT_ADMIN"}}';

SELECT throws_ok(
  $$ SELECT public.amend_contract_financial_terms(
       'aaaa0000-0000-4000-8000-0000000000ca',
       NULL, 9000, now(), 'cross org') $$,
  'P0001', 'Contract not found or unauthorized',
  'Org B amend em contrato da Org A -> rejeitado (anti-oracle)'
);

SELECT * FROM finish();
ROLLBACK;
