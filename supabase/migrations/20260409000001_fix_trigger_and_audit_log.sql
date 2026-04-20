-- Suppress notices from DROP IF EXISTS on fresh reset
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: 20260409000001 — Phase 9.3 Post-Test Fixes
--
-- Fix 1: auto_enqueue_sanction_recommended — handle NULL contract_id
--   The trigger used NEW.contract_id directly. When the ledger entry has no
--   contract_id (manual Studio insert / DataSeeder insert), the NOT NULL
--   constraint on sanction_review_queue.contract_id caused a violation.
--   COALESCE mirrors the same pattern already used for set_id.
--
-- Fix 2: system_audit_log — add organization_name TEXT column
--   Mirrors the tenant_billing_events pattern: human-readable without JOIN.
--   Backfilled as NULL for existing rows (no data loss).
--
-- Fix 3: super_admin_check_cnpj_exists RPC
--   Allows the wizard to do a real-time CNPJ uniqueness check before advancing
--   to step 2 — preventing duplicate-CNPJ errors from surfacing only at submit.
-- =============================================================================

-- ── Fix 1: Rebuild trigger with COALESCE for nullable contract_id ─────────────

CREATE OR REPLACE FUNCTION public.auto_enqueue_sanction_recommended()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.type = 'SANCTION_RECOMMENDED' THEN
    INSERT INTO public.sanction_review_queue (
      organization_id,
      ledger_entry_id,
      set_id,
      contract_id,
      verdict_evidence,
      status,
      created_at
    ) VALUES (
      NEW.organization_id,
      NEW.id,
      COALESCE(NEW.set_id, ''),
      COALESCE(NEW.contract_id::text, ''),   -- was: NEW.contract_id (NULL violation)
      NEW.payload -> 'verdict_evidence',
      'pending',
      NOW()
    )
    ON CONFLICT (ledger_entry_id) DO NOTHING;  -- INV-24: idempotent
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger already exists — just replace the function above.
-- Re-create it anyway to be explicit and safe on fresh reset.
DROP TRIGGER IF EXISTS trg_auto_enqueue_sanction ON public.sla_audit_ledger_v2;
CREATE TRIGGER trg_auto_enqueue_sanction
  AFTER INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW EXECUTE FUNCTION public.auto_enqueue_sanction_recommended();

-- ── Fix 2: Add organization_name to system_audit_log ─────────────────────────

ALTER TABLE public.system_audit_log
  ADD COLUMN IF NOT EXISTS organization_name TEXT;

COMMENT ON COLUMN public.system_audit_log.organization_name IS
  'Human-readable org name — denormalized for readability without JOIN (mirrors tenant_billing_events pattern).';

-- ── Fix 3: CNPJ uniqueness check RPC (for wizard real-time validation) ────────

CREATE OR REPLACE FUNCTION public.super_admin_check_cnpj_exists(p_cnpj TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organizations
    WHERE cnpj = trim(p_cnpj)
    LIMIT 1
  );
$$;

-- Only authenticated users may call this (SuperAdmin wizard).
REVOKE ALL ON FUNCTION public.super_admin_check_cnpj_exists(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_check_cnpj_exists(TEXT) TO authenticated;
