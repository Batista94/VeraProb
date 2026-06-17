BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

-- =============================================================================
-- pgTAP: read_infraction_context RPC
-- Migration: 20260819000003_read_infraction_context_rpc.sql
-- Focus: projection correctness; access_count NOT incremented (no-burn);
--   all invalid paths → single opaque 42501 (INV-26 anti-oracle).
-- =============================================================================

-- ── Seeds ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains, logo_url
) VALUES (
  'b3b3b3b3-0000-0000-0000-000000000001', 'Org IC BUG3', 'Org IC BUG3 SA',
  'b3b30000000001', 'America/Sao_Paulo', 'BRL', 'enterprise', 50, 5, 3000,
  300, 15, 'bug3@test.com', 'EXT_BUG3', 'LOGISTICS', ARRAY['bug3.com'],
  'https://cdn.example.com/logos/bug3.png'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'b3b3b3b3-0000-0000-0000-000000000002',
  'b3b3b3b3-0000-0000-0000-000000000001',
  'b3b3b3b3-0000-0000-0000-0000000000f1',
  'set-ic-bug3',
  'b3b3b3b3-0000-0000-0000-000000000003',
  jsonb_build_object(
    'fine_cents',                        50000,
    'delta_value',                       7.5,
    'threshold_value',                   5.0,
    'primary_evidence_timestamp_utc',    '2026-08-19T10:00:00Z',
    'primary_evidence_lat',              '-23.5505',
    'primary_evidence_lng',              '-46.6333'
  ),
  'pending',
  'BUG3-001'
) ON CONFLICT (id) DO NOTHING;

-- Four tokens: valid / expired / revoked / exhausted
INSERT INTO public.dispute_portal_tokens
  (token, organization_id, queue_entry_id, created_by_user_id,
   expires_at_utc, max_access_count, created_at_utc)
VALUES
  -- T_VALID
  ('b3b30001-0000-0000-0000-000000000000',
   'b3b3b3b3-0000-0000-0000-000000000001',
   'b3b3b3b3-0000-0000-0000-000000000002',
   'b3b3b3b3-0000-0000-0000-0000000000b1',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  -- T_EXPIRED: created 3h ago so expires_at_utc (NOW()-1h) > created_at_utc (NOW()-3h)
  --            satisfies chk_dpt_expires_window while remains past-dated vs NOW().
  ('b3b30002-0000-0000-0000-000000000000',
   'b3b3b3b3-0000-0000-0000-000000000001',
   'b3b3b3b3-0000-0000-0000-000000000002',
   'b3b3b3b3-0000-0000-0000-0000000000b1',
   NOW() - INTERVAL '1 hour', 5, NOW() - INTERVAL '3 hours'),
  -- T_REVOKED (revoked_at_utc set below)
  ('b3b30003-0000-0000-0000-000000000000',
   'b3b3b3b3-0000-0000-0000-000000000001',
   'b3b3b3b3-0000-0000-0000-000000000002',
   'b3b3b3b3-0000-0000-0000-0000000000b1',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  -- T_EXHAUSTED (access_count >= max_access_count)
  ('b3b30004-0000-0000-0000-000000000000',
   'b3b3b3b3-0000-0000-0000-000000000001',
   'b3b3b3b3-0000-0000-0000-000000000002',
   'b3b3b3b3-0000-0000-0000-0000000000b1',
   NOW() + INTERVAL '24 hours', 5, NOW())
ON CONFLICT (token) DO NOTHING;

UPDATE public.dispute_portal_tokens
   SET revoked_at_utc = NOW()
 WHERE 'b3b30003-0000-0000-0000-000000000000' = token;

UPDATE public.dispute_portal_tokens
   SET access_count = 5
 WHERE 'b3b30004-0000-0000-0000-000000000000' = token;

-- T1: read_infraction_context function exists.
SELECT has_function(
  'public', 'read_infraction_context',
  ARRAY['uuid'],
  'T1: read_infraction_context exists with 1-arg signature'
);

-- T2: read_infraction_context is SECURITY DEFINER.
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'read_infraction_context'),
  true,
  'T2: read_infraction_context is SECURITY DEFINER'
);

-- T3: anon may EXECUTE (carrier-facing, INV-26).
SELECT ok(
  has_function_privilege('anon',
    'public.read_infraction_context(uuid)', 'EXECUTE'),
  'T3: anon may EXECUTE read_infraction_context'
);

-- T4: authenticated may EXECUTE.
SELECT ok(
  has_function_privilege('authenticated',
    'public.read_infraction_context(uuid)', 'EXECUTE'),
  'T4: authenticated may EXECUTE read_infraction_context'
);

-- T5: service_role may NOT EXECUTE (REVOKE FROM PUBLIC strips it, INV-22).
SELECT ok(
  NOT has_function_privilege('service_role',
    'public.read_infraction_context(uuid)', 'EXECUTE'),
  'T5: service_role may NOT EXECUTE read_infraction_context'
);

-- T6: valid token → non-NULL result.
SELECT ok(
  (SELECT public.read_infraction_context('b3b30001-0000-0000-0000-000000000000') IS NOT NULL),
  'T6: valid token returns non-NULL JSONB projection'
);

-- T7: asset_identifier maps to vehicle_plate.
SELECT is(
  (SELECT public.read_infraction_context('b3b30001-0000-0000-0000-000000000000')
         ->> 'asset_identifier'),
  'BUG3-001',
  'T7: asset_identifier = vehicle_plate from sanction_review_queue'
);

-- T8: penalty_value_cents maps to fine_cents in verdict_evidence.
SELECT is(
  (SELECT (public.read_infraction_context('b3b30001-0000-0000-0000-000000000000')
          ->> 'penalty_value_cents')::int),
  50000,
  'T8: penalty_value_cents = fine_cents from verdict_evidence JSONB'
);

-- T9: access_count NOT incremented after read (no-burn guarantee).
SELECT is(
  (SELECT access_count FROM public.dispute_portal_tokens
    WHERE 'b3b30001-0000-0000-0000-000000000000' = token),
  0,
  'T9: access_count unchanged after read_infraction_context call (no burn)'
);

-- T10: expired token → opaque 42501 (INV-26 anti-oracle).
SELECT throws_ok(
  $$ SELECT public.read_infraction_context('b3b30002-0000-0000-0000-000000000000') $$,
  '42501', NULL,
  'T10: expired token returns opaque 42501'
);

-- T11: revoked token → opaque 42501.
SELECT throws_ok(
  $$ SELECT public.read_infraction_context('b3b30003-0000-0000-0000-000000000000') $$,
  '42501', NULL,
  'T11: revoked token returns opaque 42501'
);

-- T12: exhausted token → opaque 42501.
SELECT throws_ok(
  $$ SELECT public.read_infraction_context('b3b30004-0000-0000-0000-000000000000') $$,
  '42501', NULL,
  'T12: exhausted token returns opaque 42501'
);

-- T13: unknown token (never seeded) → opaque 42501.
SELECT throws_ok(
  $$ SELECT public.read_infraction_context('ffffffff-ffff-ffff-ffff-ffffffffffff') $$,
  '42501', NULL,
  'T13: unknown token returns opaque 42501'
);

SELECT * FROM finish();
ROLLBACK;
