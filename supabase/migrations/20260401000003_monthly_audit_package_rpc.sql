-- =============================================================================
-- Phase 7.1 — Evidence & Audit Exports: Burden of Proof
-- Migration 3/3: Monthly Audit Package RPC (idempotency gate)
-- =============================================================================
-- EXECUTION ORDER: run after 20260401000002_shadow_mode_simulations.sql.
--
-- D3-Challenger design: This RPC is an IDEMPOTENCY GATE only.
-- It checks whether a sealed audit_package already exists for the given period.
-- Actual computation is delegated to the Dart AuditPackageService (INV-4).
-- The RPC is called by the Supabase Edge Function which is triggered by an
-- external scheduler (GitHub Actions cron) — avoids pg_cron (Supabase Pro).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RPC: generate_monthly_audit_package
--
-- Purpose: Idempotency check for monthly audit package generation.
-- Returns: The existing sealed package ID if one already exists, else NULL.
--
-- The Edge Function calls this RPC first:
--   - If it returns a UUID → package already generated, skip generation.
--   - If it returns NULL  → call AuditPackageService.createDraftAndSeal().
--
-- Security: SECURITY DEFINER runs as the function owner (postgres).
-- Callers must pass a valid organization_id that they own (enforced by RLS
-- on audit_packages — the calling JWT must match).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION generate_monthly_audit_package(
  p_organization_id  UUID,
  p_year             INT,
  p_month            INT,
  p_contract_id      UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_start  TIMESTAMPTZ;
  v_period_end    TIMESTAMPTZ;
  v_existing_id   UUID;
BEGIN
  -- Compute period boundaries (first to last day of month, UTC)
  v_period_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'UTC');
  v_period_end   := (v_period_start + INTERVAL '1 month') - INTERVAL '1 microsecond';

  -- Idempotency check: return existing sealed package ID if found
  SELECT id INTO v_existing_id
  FROM audit_packages
  WHERE organization_id   = p_organization_id
    AND (p_contract_id IS NULL OR contract_id = p_contract_id)
    AND period_start_utc  = v_period_start
    AND period_end_utc    = v_period_end
    AND status            = 'sealed'
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN v_existing_id;  -- NULL if no package exists yet
END;
$$;

-- Revoke public execution; only authenticated users (service_role or JWT) may call.
REVOKE EXECUTE ON FUNCTION generate_monthly_audit_package(UUID, INT, INT, UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION generate_monthly_audit_package(UUID, INT, INT, UUID) TO authenticated;
GRANT  EXECUTE ON FUNCTION generate_monthly_audit_package(UUID, INT, INT, UUID) TO service_role;

COMMENT ON FUNCTION generate_monthly_audit_package IS
  'Idempotency gate for monthly audit package generation (Phase 7.1 / D3-Challenger). '
  'Returns the existing sealed audit_package.id for the given org/month, or NULL if none exists. '
  'Actual package computation is performed by the Dart AuditPackageService (INV-4).';
