-- Migration: Hard Quota Enforcement Triggers (Phase 9.8.D)
--
-- Adds BEFORE INSERT triggers on `vehicles` and `contracts` tables
-- that reject inserts when the tenant's quota limit has been reached.
-- NULL limit means unlimited (enterprise tier).
--
-- INV-1: Every check filters by organization_id.
-- INV-19: Limits are integers (counts), never Money.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Function: enforce vehicle quota
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.enforce_vehicle_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_vehicles INTEGER;
  v_current_count INTEGER;
BEGIN
  -- Fetch the org's vehicle quota (NULL = unlimited)
  SELECT max_vehicles
    INTO v_max_vehicles
    FROM public.organizations
   WHERE id = NEW.organization_id;

  -- NULL means unlimited — allow insert
  IF v_max_vehicles IS NULL THEN
    RETURN NEW;
  END IF;

  -- Count active vehicles for this org
  SELECT COUNT(*)
    INTO v_current_count
    FROM public.vehicles
   WHERE organization_id = NEW.organization_id;

  IF v_current_count >= v_max_vehicles THEN
    RAISE EXCEPTION 'Cota de veículos atingida: limite é % para esta organização.', v_max_vehicles
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- Drop existing trigger if any (idempotent)
DROP TRIGGER IF EXISTS trg_enforce_vehicle_quota ON public.vehicles;

CREATE TRIGGER trg_enforce_vehicle_quota
  BEFORE INSERT ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_vehicle_quota();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Function: enforce contract quota
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.enforce_contract_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_contracts INTEGER;
  v_current_count INTEGER;
BEGIN
  -- Fetch the org's active-contract quota (NULL = unlimited)
  SELECT max_active_contracts
    INTO v_max_contracts
    FROM public.organizations
   WHERE id = NEW.organization_id;

  -- NULL means unlimited — allow insert
  IF v_max_contracts IS NULL THEN
    RETURN NEW;
  END IF;

  -- Count active contracts for this org
  SELECT COUNT(*)
    INTO v_current_count
    FROM public.contracts
   WHERE organization_id = NEW.organization_id
     AND status = 'active';

  IF v_current_count >= v_max_contracts THEN
    RAISE EXCEPTION 'Cota de contratos ativos atingida: limite é % para esta organização.', v_max_contracts
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- Drop existing trigger if any (idempotent)
DROP TRIGGER IF EXISTS trg_enforce_contract_quota ON public.contracts;

CREATE TRIGGER trg_enforce_contract_quota
  BEFORE INSERT ON public.contracts
  FOR EACH ROW EXECUTE FUNCTION public.enforce_contract_quota();
