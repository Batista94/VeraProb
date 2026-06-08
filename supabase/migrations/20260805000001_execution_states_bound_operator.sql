SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: bind operator (driver) to execution_states (Asset/Operator — INV-14)
--
-- The Core is transport-agnostic: an Execution binds an Asset (vehicle) AND an
-- Operator (driver). The vehicle binding already exists (bound_vehicle_id); this
-- adds the missing operator binding so downstream forensic denormalization can
-- resolve the operator name from the authoritative registry.
--
-- INV-14: Asset/Operator/Execution — operator binding completes the triad.
-- INV-22: org-scoped FK; the resolving join filters by organization_id.
-- INV-DB: additive nullable column — zero-downtime, no blocking ALTER.
-- =============================================================================

-- ── A: Add nullable operator binding (references the driver registry) ─────────
ALTER TABLE public.execution_states
  ADD COLUMN IF NOT EXISTS bound_operator_id UUID NULL
  REFERENCES public.drivers(id) ON DELETE SET NULL;

-- ── B: Recreate create_execution_for_operator to persist the operator binding ──
-- The operator id (p_driver_id) was previously written only to the ledger
-- payload (20260424000004). Persisting it on execution_states lets the sanction
-- enqueue trigger resolve the operator name without parsing the ledger.
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
    bound_operator_id,
    status,
    created_at_utc
  ) VALUES (
    v_set_id,
    p_contract_id,
    p_organization_id,
    p_window_start_utc,
    p_window_end_utc,
    p_vehicle_id,
    p_driver_id,
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
      'created_by',        (auth.jwt() ->> 'sub')::uuid,
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
  'OCC operator creates a planned trip without direct DB access. Persists Asset + Operator bindings on execution_states (INV-14). Returns deterministic set_id. INV-1 JWT guard, INV-3 ledger, INV-15 idempotent.';
