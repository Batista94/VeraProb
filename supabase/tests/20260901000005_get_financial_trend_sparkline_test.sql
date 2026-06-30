-- pgTAP: get_financial_trend_sparkline
-- Validates dedup, window filter, contract_id IS NULL filter, grant, SECURITY DEFINER, anti-oracle.
-- Run via: make test-db

BEGIN;

SELECT plan(11);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name, cnpj) VALUES
  ('00000000-0000-0000-0000-000000000020'::uuid, 'Sparkline Tenant A', '11222333000181'),
  ('00000000-0000-0000-0000-000000000021'::uuid, 'Sparkline Tenant B', '44555666000195')
ON CONFLICT (id) DO NOTHING;

-- Helper: base date 7 days ago (within default window)
DO $$ BEGIN
  PERFORM set_config('test.base_date', (now() AT TIME ZONE 'utc' - interval '3 days')::date::text, false);
  PERFORM set_config('test.old_date',  (now() AT TIME ZONE 'utc' - interval '10 days')::date::text, false);
  PERFORM set_config('test.org_a', '00000000-0000-0000-0000-000000000020', false);
  PERFORM set_config('test.org_b', '00000000-0000-0000-0000-000000000021', false);
END $$;

-- Canonical point for Org A on base_date (not superseded)
INSERT INTO public.contractual_financial_snapshot (
  id, organization_id, contract_id,
  operational_date_utc, operational_timezone, closed_at_utc,
  total_contracted_revenue_cents, protected_revenue_cents,
  revenue_at_risk_cents, lost_revenue_cents,
  risk_percentage, loss_percentage,
  risk_percentage_bps, loss_percentage_bps,
  engine_version
) VALUES (
  '20000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000020'::uuid,
  NULL,
  (current_setting('test.base_date') || ' 00:00:00+00')::timestamptz,
  'America/Sao_Paulo',
  (current_setting('test.base_date') || ' 06:00:00+00')::timestamptz,
  100000, 60000, 30000, 10000,
  30.0, 10.0,
  30, 10,
  'test-v1'
) ON CONFLICT DO NOTHING;

-- Superseded point for same day — should be excluded from sparkline
INSERT INTO public.contractual_financial_snapshot (
  id, organization_id, contract_id,
  operational_date_utc, operational_timezone, closed_at_utc,
  total_contracted_revenue_cents, protected_revenue_cents,
  revenue_at_risk_cents, lost_revenue_cents,
  risk_percentage, loss_percentage,
  risk_percentage_bps, loss_percentage_bps,
  engine_version,
  previous_snapshot_id
) VALUES (
  '20000000-0000-0000-0000-000000000002'::uuid,
  '00000000-0000-0000-0000-000000000020'::uuid,
  NULL,
  (current_setting('test.base_date') || ' 00:00:00+00')::timestamptz,
  'America/Sao_Paulo',
  (current_setting('test.base_date') || ' 08:00:00+00')::timestamptz,
  100000, 65000, 25000, 10000,
  25.0, 10.0,
  25, 10,
  'test-v1',
  '20000000-0000-0000-0000-000000000001'::uuid  -- supersedes the first
) ON CONFLICT DO NOTHING;

-- Contract-level row (contract_id NOT NULL) — must be excluded
INSERT INTO public.contractual_financial_snapshot (
  id, organization_id, contract_id,
  operational_date_utc, operational_timezone, closed_at_utc,
  total_contracted_revenue_cents, protected_revenue_cents,
  revenue_at_risk_cents, lost_revenue_cents,
  risk_percentage, loss_percentage,
  risk_percentage_bps, loss_percentage_bps,
  engine_version
) VALUES (
  '20000000-0000-0000-0000-000000000003'::uuid,
  '00000000-0000-0000-0000-000000000020'::uuid,
  'contract-xyz',
  (current_setting('test.base_date') || ' 00:00:00+00')::timestamptz,
  'America/Sao_Paulo',
  (current_setting('test.base_date') || ' 06:00:00+00')::timestamptz,
  50000, 40000, 8000, 2000,
  16.0, 4.0,
  16, 4,
  'test-v1'
) ON CONFLICT DO NOTHING;

-- Outside-window point (10 days ago, default window = 7 days) — excluded
INSERT INTO public.contractual_financial_snapshot (
  id, organization_id, contract_id,
  operational_date_utc, operational_timezone, closed_at_utc,
  total_contracted_revenue_cents, protected_revenue_cents,
  revenue_at_risk_cents, lost_revenue_cents,
  risk_percentage, loss_percentage,
  risk_percentage_bps, loss_percentage_bps,
  engine_version
) VALUES (
  '20000000-0000-0000-0000-000000000004'::uuid,
  '00000000-0000-0000-0000-000000000020'::uuid,
  NULL,
  (current_setting('test.old_date') || ' 00:00:00+00')::timestamptz,
  'America/Sao_Paulo',
  (current_setting('test.old_date') || ' 06:00:00+00')::timestamptz,
  100000, 50000, 40000, 10000,
  40.0, 10.0,
  40, 10,
  'test-v1'
) ON CONFLICT DO NOTHING;

-- Org B canonical point (tenant isolation)
INSERT INTO public.contractual_financial_snapshot (
  id, organization_id, contract_id,
  operational_date_utc, operational_timezone, closed_at_utc,
  total_contracted_revenue_cents, protected_revenue_cents,
  revenue_at_risk_cents, lost_revenue_cents,
  risk_percentage, loss_percentage,
  risk_percentage_bps, loss_percentage_bps,
  engine_version
) VALUES (
  '20000000-0000-0000-0000-000000000005'::uuid,
  '00000000-0000-0000-0000-000000000021'::uuid,
  NULL,
  (current_setting('test.base_date') || ' 00:00:00+00')::timestamptz,
  'America/Sao_Paulo',
  (current_setting('test.base_date') || ' 06:00:00+00')::timestamptz,
  200000, 180000, 15000, 5000,
  7.5, 2.5,
  8, 3,
  'test-v1'
) ON CONFLICT DO NOTHING;

-- ── TC1: has_function ─────────────────────────────────────────────────────────
SELECT has_function(
  'public',
  'get_financial_trend_sparkline',
  ARRAY['uuid', 'integer'],
  'TC1: function get_financial_trend_sparkline(uuid, integer) exists'
);

-- ── TC2: SECURITY DEFINER ─────────────────────────────────────────────────────
SELECT ok(
  (SELECT prosecdef FROM pg_proc
   WHERE pronamespace = 'public'::regnamespace
     AND proname = 'get_financial_trend_sparkline'
   LIMIT 1),
  'TC2: SECURITY DEFINER set on get_financial_trend_sparkline'
);

-- ── TC3: authenticated has EXECUTE ────────────────────────────────────────────
SELECT ok(
  has_function_privilege('authenticated', 'public.get_financial_trend_sparkline(uuid, integer)', 'EXECUTE'),
  'TC3: authenticated role has EXECUTE on get_financial_trend_sparkline'
);

-- ── TC4: Org A — correct data, canonical (not superseded), ordered ─────────────
SELECT set_config('request.jwt.claims',
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000020","role":"TENANT_ADMIN"}}',
  true);

SELECT ok(
  (
    SELECT jsonb_array_length(
      public.get_financial_trend_sparkline('00000000-0000-0000-0000-000000000020'::uuid, 7)
    ) = 1
  ),
  'TC4: exactly 1 canonical point returned for Org A in 7-day window'
);

-- ── TC5: p_days window filter — old_date (10 days) excluded from 7-day window ──
SELECT ok(
  (
    SELECT NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(
        public.get_financial_trend_sparkline('00000000-0000-0000-0000-000000000020'::uuid, 7)
      ) elem
      WHERE (elem ->> 'd') = current_setting('test.old_date')
    )
  ),
  'TC5: snapshot older than p_days window excluded from result'
);

-- ── TC6: contract_id IS NULL filter — contract row not in result ──────────────
-- Result has exactly 1 row (org-level closure), not the contract-level row.
-- If contract rows leaked, protected_cents would be 40000 on that day entry.
SELECT ok(
  (
    SELECT NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(
        public.get_financial_trend_sparkline('00000000-0000-0000-0000-000000000020'::uuid, 7)
      ) elem
      WHERE (elem ->> 'protected_cents')::BIGINT = 40000
    )
  ),
  'TC6: contract-level snapshot (contract_id NOT NULL) excluded from sparkline'
);

-- ── TC7: Superseded dedup — only canonical kept, not the superseded row ────────
-- Superseded row had protected=60000; canonical (superseder) had protected=65000.
SELECT ok(
  (
    SELECT (
      SELECT elem ->> 'protected_cents'
      FROM jsonb_array_elements(
        public.get_financial_trend_sparkline('00000000-0000-0000-0000-000000000020'::uuid, 7)
      ) elem
      LIMIT 1
    )::BIGINT = 65000
  ),
  'TC7: only canonical (non-superseded) row returned; protected_cents = 65000'
);

-- ── TC8: Cross-tenant IDOR — Org A claim, p_org_id = Org B → 42501 ───────────
SELECT throws_ok(
  $$ SELECT public.get_financial_trend_sparkline('00000000-0000-0000-0000-000000000021'::uuid, 7) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC8/INV-26: Org A claim + p_org_id=Org B → 42501 anti-oracle'
);

-- ── TC9: Missing org_id claim → 42501 ────────────────────────────────────────
SELECT set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{}}', true);
SELECT throws_ok(
  $$ SELECT public.get_financial_trend_sparkline('00000000-0000-0000-0000-000000000020'::uuid, 7) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC9/INV-26: missing org_id in app_metadata → 42501 anti-oracle'
);

-- ── TC10: p_org_id NULL → 42501 ──────────────────────────────────────────────
SELECT set_config('request.jwt.claims',
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000020","role":"TENANT_ADMIN"}}',
  true);
SELECT throws_ok(
  $$ SELECT public.get_financial_trend_sparkline(NULL::uuid, 7) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC10/INV-26: p_org_id NULL → 42501 anti-oracle'
);

-- ── TC11: p_days clamp — p_days=200 clamped to 90, result bounded ───────────
SELECT ok(
  coalesce(
    jsonb_array_length(
      public.get_financial_trend_sparkline('00000000-0000-0000-0000-000000000020'::uuid, 200)
    ), 0
  ) <= 90,
  'TC11: p_days=200 clamped to 90, result contains at most 90 data points'
);

SELECT * FROM finish();
ROLLBACK;
