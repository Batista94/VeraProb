-- =============================================================================
-- Migration: Phase 10.8 — SLA Sandbox GC Worker + RBAC Permission
--
-- 1. gc_sandbox_simulations(): batched TTL cleanup (SECURITY DEFINER).
-- 2. Seed 'sandbox:simulate' permission into tenant_permissions.
--
-- INV-1:  GC is org-agnostic (service_role, cross-tenant).
-- INV-3:  Shadow Ledger is explicitly NOT part of the financial audit trail.
--         GC-driven DELETE is architecturally valid.
-- INV-6:  Expiry comparison uses NOW() (TIMESTAMPTZ).
-- INV-22: Permission gated by RBAC (sandbox:simulate).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. GC Function ─────────────────────────────────────────────────────────
-- Batched deletion of expired sandbox sessions and their results.
-- Uses app.gc_sandbox GUC to bypass immutability triggers.
-- Logged to system_audit_log for forensic traceability.

CREATE OR REPLACE FUNCTION public.gc_sandbox_simulations(
  p_batch_size INT DEFAULT 1000
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_total_deleted INT := 0;
  v_batch         INT;
  v_expired_ids   UUID[];
BEGIN
  -- Enable GC bypass on immutability triggers
  PERFORM set_config('app.gc_sandbox', 'true', true);

  LOOP
    -- Find expired sessions (batch)
    SELECT ARRAY(
      SELECT id FROM public.sandbox_simulation_sessions
       WHERE expires_at_utc < NOW()
       LIMIT p_batch_size
    ) INTO v_expired_ids;

    EXIT WHEN v_expired_ids IS NULL OR array_length(v_expired_ids, 1) IS NULL;

    -- Delete results first (FK cascade handles this, but explicit for clarity)
    DELETE FROM public.sandbox_simulation_results
     WHERE session_id = ANY(v_expired_ids);
    GET DIAGNOSTICS v_batch = ROW_COUNT;
    v_total_deleted := v_total_deleted + v_batch;

    -- Delete sessions
    DELETE FROM public.sandbox_simulation_sessions
     WHERE id = ANY(v_expired_ids);
    GET DIAGNOSTICS v_batch = ROW_COUNT;
    v_total_deleted := v_total_deleted + v_batch;

    -- Exit if batch was smaller than limit (no more to process)
    EXIT WHEN array_length(v_expired_ids, 1) < p_batch_size;
  END LOOP;

  -- Disable GC bypass
  PERFORM set_config('app.gc_sandbox', '', true);

  -- Log GC execution (forensic traceability)
  IF v_total_deleted > 0 THEN
    INSERT INTO public.system_audit_log
        (event_type, severity, actor_type, source, payload)
    VALUES (
      'SANDBOX_GC_EXECUTED', 'info', 'SYSTEM', 'gc_sandbox_simulations',
      jsonb_build_object(
        'deleted_rows', v_total_deleted,
        'executed_at_utc', NOW()
      )
    );
  END IF;

  RETURN v_total_deleted;
END;
$$;

COMMENT ON FUNCTION public.gc_sandbox_simulations IS
  'SLA Sandbox GC: batched deletion of expired simulation sessions. '
  'Uses app.gc_sandbox GUC to bypass immutability triggers. '
  'Logged to system_audit_log. Phase 10.8.';

-- Only service_role can invoke GC (no tenant access)
REVOKE ALL ON FUNCTION public.gc_sandbox_simulations(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gc_sandbox_simulations(INT) TO service_role;

-- ── 2. RBAC Permission Seed ─────────────────────────────────────────────────
-- Adds 'sandbox:simulate' to the global permission dictionary.
-- Tenant Admins must have this permission to invoke simulate_sla_sandbox().

INSERT INTO public.tenant_permissions
  (key, module, action, label_pt, description, is_sensitive, is_scopable)
VALUES
  ('sandbox:simulate', 'sandbox', 'simulate',
   'Simular SLA (What-If)',
   'Executar simulações What-If de regras SLA contra dados históricos (ROI Simulator)',
   false, true)
ON CONFLICT (key) DO NOTHING;

-- ── 3. Retroactive grant to existing admin roles ────────────────────────────
-- Any role with 'roles:manage' (full admin) gets sandbox:simulate automatically
-- so existing admins can use the feature without manual reconfiguration.

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
SELECT tenant_role_id, 'sandbox:simulate'
  FROM public.tenant_role_permissions
 WHERE permission_key = 'roles:manage'
ON CONFLICT (tenant_role_id, permission_key) DO NOTHING;
