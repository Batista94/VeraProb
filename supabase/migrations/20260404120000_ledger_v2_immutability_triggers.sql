-- =============================================================================
-- Migration: sla_audit_ledger_v2 DB-level immutability (INV-1)
--
-- REVOKE alone does not block service_role. Triggers fire before ALL operations
-- regardless of role, ensuring the ledger remains truly append-only at the
-- Postgres level — not just at the RLS/permissions level.
-- =============================================================================

-- Shared trigger function reused by both triggers below.
CREATE OR REPLACE FUNCTION public.prevent_ledger_v2_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'sla_audit_ledger_v2 is immutable (INV-1). Operation: %, id: %',
    TG_OP,
    OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

-- Block UPDATE
DROP TRIGGER IF EXISTS trg_ledger_v2_no_update ON public.sla_audit_ledger_v2;
CREATE TRIGGER trg_ledger_v2_no_update
  BEFORE UPDATE ON public.sla_audit_ledger_v2
  FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_v2_mutation();

-- Block DELETE
DROP TRIGGER IF EXISTS trg_ledger_v2_no_delete ON public.sla_audit_ledger_v2;
CREATE TRIGGER trg_ledger_v2_no_delete
  BEFORE DELETE ON public.sla_audit_ledger_v2
  FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_v2_mutation();
