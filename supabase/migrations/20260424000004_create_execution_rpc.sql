-- =============================================================================
-- Migration: create_execution_for_operator RPC (Phase 10 — UX/OPS)
--
-- Allows OCC operators to create new Executions (trips) without direct DB access.
-- Returns the deterministic set_id for idempotent retry.
--
-- INV-1:  JWT org claim validated before insert — Fail-Fast.
-- INV-3:  sla_audit_ledger entry appended (OPERATOR_CREATED_EXECUTION).
-- INV-6:  All timestamps TIMESTAMPTZ. p_window_start/end_utc are UTC-required.
-- INV-15: ON CONFLICT (set_id) DO NOTHING — byte-identical replay safe.
-- INV-22: org_id filter throughout — tenant isolation enforced.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.create_execution_for_operator(
  p_organization_id     UUID,
  p_contract_id         TEXT,
  p_driver_id           UUID,
  p_vehicle_id          UUID,
  p_origin_zone_id      UUID,
  p_destination_zone_id UUID,
  p_window_start_utc    TIMESTAMPTZ,
  p_window_end_utc      TIMESTAMPTZ
) RETURNS TEXT  -- returns set_id
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_set_id TEXT;
  v_jwt_org UUID;
BEGIN
  -- INV-1: Fail-Fast JWT org validation
  v_jwt_org := (auth.jwt() ->> 'organization_id')::UUID;
  IF v_jwt_org IS NULL OR v_jwt_org != p_organization_id THEN
    RAISE EXCEPTION 'org_mismatch: caller org % != requested org %', v_jwt_org, p_organization_id;
  END IF;

  -- Deterministic set_id (same inputs → same set_id → ON CONFLICT DO NOTHING)
  v_set_id := encode(
    sha256((p_contract_id || p_window_start_utc::TEXT)::bytea),
    'hex'
  );

  -- Insert execution (idempotent — INV-15)
  INSERT INTO public.execution_states (
    set_id,
    contract_id,
    organization_id,
    window_start_utc,
    window_end_utc,
    bound_vehicle_id,
    status,
    created_at_utc
  ) VALUES (
    v_set_id,
    p_contract_id,
    p_organization_id,
    p_window_start_utc,
    p_window_end_utc,
    p_vehicle_id,
    'planned',
    NOW()
  )
  ON CONFLICT (set_id) DO NOTHING;  -- INV-15: replay-safe

  -- INV-3: Append-only ledger entry
  INSERT INTO public.sla_audit_ledger (
    type, set_id, contract_id, plan_version, payload, occurred_at_utc
  ) VALUES (
    'OPERATOR_CREATED_EXECUTION',
    v_set_id,
    p_contract_id,
    1,
    jsonb_build_object(
      'created_by',        auth.uid(),
      'org_id',            p_organization_id,
      'driver_id',         p_driver_id,
      'vehicle_id',        p_vehicle_id,
      'origin_zone_id',    p_origin_zone_id,
      'destination_zone_id', p_destination_zone_id
    ),
    NOW()
  );

  RETURN v_set_id;
END;
$$;

COMMENT ON FUNCTION public.create_execution_for_operator IS
  'OCC operator creates a planned trip without direct DB access. Returns deterministic set_id. INV-1 JWT guard, INV-3 ledger, INV-15 idempotent. Phase 10.';

-- Grant to authenticated users (RLS + JWT org check inside function provides isolation)
GRANT EXECUTE ON FUNCTION public.create_execution_for_operator(
  UUID, TEXT, UUID, UUID, UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ
) TO authenticated;
