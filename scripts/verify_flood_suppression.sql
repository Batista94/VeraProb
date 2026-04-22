-- ============================================================================
-- Verification Script: Bloco 5 Anti-Flood — Smart Debounce Proof
-- Run AFTER applying migration 20260430000005_alert_flood_suppression.sql
--
-- Expected result: 10 INSERT attempts → 1 row in operational_alerts
-- ============================================================================

BEGIN;

-- ── Setup: deterministic test org ────────────────────────────────────────────
-- Uses a fixed UUID so the test is repeatable and cleanup is safe.

DO $$
DECLARE
  v_test_org_id UUID := '00000000-0000-0000-0000-ffffffffffff';
  v_count       INT;
BEGIN
  -- Ensure test org exists (idempotent)
  INSERT INTO public.organizations (id, name, slug)
  VALUES (v_test_org_id, '__flood_test__', '__flood_test__')
  ON CONFLICT (id) DO NOTHING;

  -- ── Fire 10 identical TELEGRAM_ORPHAN alerts in rapid succession ───────────
  FOR i IN 1..10 LOOP
    INSERT INTO public.operational_alerts (
      organization_id,
      entity_id,
      contract_id,
      alert_type,
      severity,
      status,
      source,
      triggering_event_id,
      context
    ) VALUES (
      v_test_org_id,
      '999999999',                          -- same entity_id (chat_id)
      'TELEGRAM_ORPHAN',
      'TELEGRAM_ORPHAN',
      'CRITICAL',
      'ACTIVE',
      'telegram',
      gen_random_uuid(),                    -- unique correlationId per insert (mimics Edge Function)
      jsonb_build_object('iteration', i)
    );
  END LOOP;

  -- ── Assert: exactly 1 alert survived ───────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM public.operational_alerts
  WHERE organization_id = v_test_org_id
    AND entity_id = '999999999'
    AND alert_type = 'TELEGRAM_ORPHAN'
    AND status = 'ACTIVE';

  IF v_count = 1 THEN
    RAISE NOTICE '✅ PASS: 10 inserts → % alert (flood suppressed)', v_count;
  ELSE
    RAISE EXCEPTION '❌ FAIL: expected 1 alert, got %', v_count;
  END IF;
END $$;

-- Rollback so no test data persists
ROLLBACK;
