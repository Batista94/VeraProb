-- =============================================================================
-- pgTAP: INV-6 Backdating + CAS Functional Tests
--
-- Tests check_and_close_execution_autonomously 2-hour anti-spoof window
-- and INV-15 first-write-wins CAS on destination_zone_entered_at_utc.
--
-- Run via: supabase test
-- =============================================================================

BEGIN;
SELECT plan(6);

-- ── Fixtures ─────────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_org_id  UUID := 'f9000001-0000-0000-0000-000000000001';
  v_zone_id UUID := 'f9000002-0000-0000-0000-000000000001';
  v_plan_id UUID := 'f9000003-0000-0000-0000-000000000001';
  v_set     TEXT;
BEGIN
  INSERT INTO public.organizations (id, name)
  VALUES (v_org_id, 'BDT Backdating Test Org')
  ON CONFLICT (id) DO NOTHING;

  -- Destination zone at (0,0) with 50 km radius (max allowed by CHECK constraint)
  INSERT INTO public.operational_zones (id, organization_id, name, latitude, longitude, radius_meters)
  VALUES (v_zone_id, v_org_id, 'BDT Zone', 0.0, 0.0, 50000)
  ON CONFLICT (id) DO NOTHING;

  -- Parent plan_declaration required by CSE FK
  INSERT INTO public.plan_declarations (id, contract_id, declared_at_utc, declared_by_user_id, plan_version, original_file_hash)
  VALUES (v_plan_id, 'BDT-CONTRACT', NOW(), 'test-system', 1, 'bdt-test-hash-0000000000000000')
  ON CONFLICT (id) DO NOTHING;

  -- Helper: create CSE + execution_states pair for a given set_id and optional entered_at
  FOREACH v_set IN ARRAY ARRAY['BDT-SET-01','BDT-SET-02','BDT-SET-03','BDT-SET-04'] LOOP
    INSERT INTO public.contractual_service_executions (
      set_id, plan_declaration_id,
      scheduled_start_time_utc, scheduled_end_time_utc,
      start_latitude, start_longitude, start_radius_meters,
      end_latitude, end_longitude, end_radius_meters,
      contractual_value_cents, no_show_penalty_multiplier,
      destination_zone_id
    ) VALUES (
      v_set, v_plan_id,
      NOW(), NOW() + INTERVAL '8 hours',
      0.0, 0.0, 500,
      0.0, 0.0, 500,
      10000, 1.0,
      v_zone_id
    ) ON CONFLICT (set_id) DO NOTHING;

    INSERT INTO public.execution_states (
      id, set_id, organization_id, contract_id, plan_version,
      start_latitude, start_longitude, start_radius_meters,
      contractual_value_cents, no_show_penalty_multiplier,
      window_start_utc, window_end_utc, status,
      created_at_utc, last_evaluated_at_utc, status_last_updated_at_utc
    ) VALUES (
      gen_random_uuid(), v_set, v_org_id, 'BDT-CONTRACT', 1,
      0.0, 0.0, 500,
      10000, 1.0,
      NOW(), NOW() + INTERVAL '8 hours', 'inTransit',
      NOW(), NOW(), NOW()
    ) ON CONFLICT (set_id) DO NOTHING;
  END LOOP;

  -- BDT-SET-05: pre-set entered_at (CAS preservation test)
  INSERT INTO public.contractual_service_executions (
    set_id, plan_declaration_id,
    scheduled_start_time_utc, scheduled_end_time_utc,
    start_latitude, start_longitude, start_radius_meters,
    end_latitude, end_longitude, end_radius_meters,
    contractual_value_cents, no_show_penalty_multiplier,
    destination_zone_id
  ) VALUES (
    'BDT-SET-05', v_plan_id,
    NOW(), NOW() + INTERVAL '8 hours',
    0.0, 0.0, 500,
    0.0, 0.0, 500,
    10000, 1.0,
    v_zone_id
  ) ON CONFLICT (set_id) DO NOTHING;

  INSERT INTO public.execution_states (
    id, set_id, organization_id, contract_id, plan_version,
    start_latitude, start_longitude, start_radius_meters,
    contractual_value_cents, no_show_penalty_multiplier,
    window_start_utc, window_end_utc, status,
    created_at_utc, last_evaluated_at_utc, status_last_updated_at_utc,
    destination_zone_entered_at_utc
  ) VALUES (
    gen_random_uuid(), 'BDT-SET-05', v_org_id, 'BDT-CONTRACT', 1,
    0.0, 0.0, 500,
    10000, 1.0,
    NOW(), NOW() + INTERVAL '8 hours', 'inTransit',
    NOW(), NOW(), NOW(),
    '2000-01-01T10:00:00Z'::TIMESTAMPTZ -- pre-set: CAS must not overwrite
  ) ON CONFLICT (set_id) DO NOTHING;
END $$;

-- ── Test 1: valid device_ts (10 min ago) → backdating anchor → dwell=600s → closed ──

SELECT is(
  (SELECT public.check_and_close_execution_autonomously(
    'f9000001-0000-0000-0000-000000000001'::UUID,
    'BDT-SET-01',
    0.001, 0.001,
    NOW() - INTERVAL '10 minutes'
  ) ->> 'result'),
  'closed',
  'INV-6: device_ts 10min ago → dwell=600s satisfies 300s gate → closed'
);

-- ── Test 2: NULL device_ts → fallback NOW() → dwell≈0s → dwell_pending ──────────

SELECT is(
  (SELECT public.check_and_close_execution_autonomously(
    'f9000001-0000-0000-0000-000000000001'::UUID,
    'BDT-SET-02',
    0.001, 0.001,
    NULL
  ) ->> 'result'),
  'dwell_pending',
  'INV-6: NULL device_ts → fallback NOW() → dwell≈0s → dwell_pending'
);

-- ── Test 3: future device_ts (anti-tamper) → fallback NOW() → dwell_pending ─────

SELECT is(
  (SELECT public.check_and_close_execution_autonomously(
    'f9000001-0000-0000-0000-000000000001'::UUID,
    'BDT-SET-03',
    0.001, 0.001,
    NOW() + INTERVAL '1 hour'
  ) ->> 'result'),
  'dwell_pending',
  'INV-6: future device_ts (anti-tamper) → fallback NOW() → dwell_pending'
);

-- ── Test 4: stale device_ts (3h ago, outside 2h window) → fallback → dwell_pending ─

SELECT is(
  (SELECT public.check_and_close_execution_autonomously(
    'f9000001-0000-0000-0000-000000000001'::UUID,
    'BDT-SET-04',
    0.001, 0.001,
    NOW() - INTERVAL '3 hours'
  ) ->> 'result'),
  'dwell_pending',
  'INV-6: device_ts 3h ago (outside 2h window) → fallback NOW() → dwell_pending'
);

-- ── Test 5: pre-set entered_at → CAS skipped → dwell huge → closed ───────────────

SELECT is(
  (SELECT public.check_and_close_execution_autonomously(
    'f9000001-0000-0000-0000-000000000001'::UUID,
    'BDT-SET-05',
    0.001, 0.001,
    NOW() - INTERVAL '10 minutes'
  ) ->> 'result'),
  'closed',
  'INV-15: pre-set entered_at skips CAS → dwell=years → closed'
);

-- ── Test 6: CAS first-write-wins — pre-set value must not be overwritten ─────────

SELECT is(
  (SELECT destination_zone_entered_at_utc
     FROM public.execution_states
    WHERE set_id = 'BDT-SET-05'),
  '2000-01-01T10:00:00Z'::TIMESTAMPTZ,
  'INV-15: destination_zone_entered_at_utc unchanged after close (CAS preserved)'
);

SELECT * FROM finish();
ROLLBACK;
