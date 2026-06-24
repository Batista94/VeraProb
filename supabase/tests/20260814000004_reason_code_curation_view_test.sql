BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- =============================================================================
-- pgTAP: v_reason_code_curation_candidates — Item 5.5 reason-code curation feed
-- Migration: 20260814000004_reason_code_curation_view.sql
-- Focus: security_invoker view, OTHER-category filtering (incl. LEGACY_*),
-- case/whitespace normalization + frequency, structured-code exclusion,
-- tenant isolation inherited from base-table RLS.
-- =============================================================================

-- ── Seeds (as postgres: bypasses RLS/grants) ─────────────────────────────────
INSERT INTO public.organizations (id, name, cnpj, created_at) VALUES
  ('cccccccc-0000-0000-0000-000000000001', 'Org Curation A', '00000000cu0001', NOW()),
  ('cccccccc-0000-0000-0000-000000000002', 'Org Curation B', '00000000cu0002', NOW())
ON CONFLICT (id) DO NOTHING;

-- Org A: two OTHER rows with the SAME text differing only by case/whitespace
-- (must collapse to ONE group, occurrence_count = 2), one LEGACY_UNCLASSIFIED
-- row (distinct group — proves category-based filter, not a hard-coded code),
-- one structured SENSOR_FAULT row (must be EXCLUDED), one blank-text OTHER row
-- (must be EXCLUDED by the btrim <> '' guard).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, rejection_reason_code, rejection_reason)
VALUES
  ('cccccccc-0000-0000-0000-0000000000a1', 'cccccccc-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-0000000000f1', 'set-a', 'ctr-a', '{}'::jsonb,
   'rejected', 'OTHER', 'Greve do motorista'),
  ('cccccccc-0000-0000-0000-0000000000a2', 'cccccccc-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-0000000000f2', 'set-a', 'ctr-a', '{}'::jsonb,
   'rejected', 'OTHER', '  greve do motorista   '),
  ('cccccccc-0000-0000-0000-0000000000a3', 'cccccccc-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-0000000000f3', 'set-a', 'ctr-a', '{}'::jsonb,
   'rejected', 'LEGACY_UNCLASSIFIED', 'Pane eletrica'),
  ('cccccccc-0000-0000-0000-0000000000a4', 'cccccccc-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-0000000000f4', 'set-a', 'ctr-a', '{}'::jsonb,
   'rejected', 'SENSOR_FAULT', 'structured code should be excluded'),
  ('cccccccc-0000-0000-0000-0000000000a5', 'cccccccc-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-0000000000f5', 'set-a', 'ctr-a', '{}'::jsonb,
   'rejected', 'OTHER', '    ')
ON CONFLICT (id) DO NOTHING;

-- Org B: one OTHER row — visible to postgres, invisible to an Org-A session.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, rejection_reason_code, rejection_reason)
VALUES
  ('cccccccc-0000-0000-0000-0000000000b1', 'cccccccc-0000-0000-0000-000000000002',
   'cccccccc-0000-0000-0000-0000000000e1', 'set-b', 'ctr-b', '{}'::jsonb,
   'rejected', 'OTHER', 'Bloqueio sindical')
ON CONFLICT (id) DO NOTHING;

-- ── T1: view exists ──────────────────────────────────────────────────────────
SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'public'
      AND table_name = 'v_reason_code_curation_candidates'
  ),
  'T1: v_reason_code_curation_candidates view exists'
);

-- ── T2: view is security_invoker (INV-2 / CI#11) ─────────────────────────────
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_class
    WHERE relname = 'v_reason_code_curation_candidates'
      AND relnamespace = 'public'::regnamespace
      AND 'security_invoker=true' = ANY (reloptions)
  ),
  'T2: view created WITH (security_invoker = true)'
);

-- ── T3: authenticated holds SELECT (INV-DATA-API-GRANT) ──────────────────────
SELECT ok(
  has_table_privilege('authenticated', 'public.v_reason_code_curation_candidates', 'SELECT'),
  'T3: authenticated granted SELECT on curation view'
);

-- ── T4: case/whitespace normalization collapses to ONE group, count = 2 ──────
SELECT is(
  (SELECT occurrence_count
     FROM public.v_reason_code_curation_candidates
    WHERE organization_id = 'cccccccc-0000-0000-0000-000000000001'
      AND normalized_text = 'greve do motorista'),
  2::bigint,
  'T4: case/whitespace variants collapse into one candidate (count = 2)'
);

-- ── T5: Org A yields exactly 2 groups (SENSOR_FAULT + blank excluded) ────────
SELECT is(
  (SELECT count(*)
     FROM public.v_reason_code_curation_candidates
    WHERE organization_id = 'cccccccc-0000-0000-0000-000000000001'),
  2::bigint,
  'T5: only OTHER-category non-blank text surfaces (structured/blank excluded)'
);

-- ── T6: structured (non-OTHER) reason text never appears ─────────────────────
SELECT is(
  (SELECT count(*)
     FROM public.v_reason_code_curation_candidates
    WHERE normalized_text = 'structured code should be excluded'),
  0::bigint,
  'T6: SENSOR_FAULT structured-code text excluded from curation feed'
);

-- ── T7: tenant isolation — Org-A session never sees Org-B candidates ─────────
SET ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"organization_id":"cccccccc-0000-0000-0000-000000000001",'
  || '"app_metadata":{"org_id":"cccccccc-0000-0000-0000-000000000001",'
  || '"role":"TENANT_ADMIN"}}',
  true
);

SELECT is(
  (SELECT count(*) FROM public.v_reason_code_curation_candidates),
  2::bigint,
  'T7: security_invoker inherits base RLS — Org-A sees only its 2 candidates'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
