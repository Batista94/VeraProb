-- =============================================================================
-- Migration: 20260415000001 — Fix sla_audit_ledger (v1) RLS isolation + DELETE guard
--
-- Problems:
--   1. "Ledger Read" policy was USING (true) — all authenticated users could
--      SELECT every row regardless of tenant. Org A could read Org B ledger
--      entries (INV-1 / INV-6 violation).
--
--   2. No trigger blocked DELETE on the v1 ledger. REVOKE alone does not stop
--      service_role (which has superuser rights). A trigger fires before ALL
--      operations regardless of role.
--
-- Fixes:
--   1. Replace "Ledger Read" with a tenant-scoped policy that joins through
--      contracts to derive organization_id (v1 ledger has no direct org column).
--
--   2. Add BEFORE DELETE trigger that raises restrict_violation — mirroring
--      the pattern already used on sla_audit_ledger_v2.
-- =============================================================================

-- ── 1. Fix RLS: tenant-scoped SELECT ────────────────────────────────────────

DROP POLICY IF EXISTS "Ledger Read" ON public.sla_audit_ledger;

CREATE POLICY "Ledger Read"
  ON public.sla_audit_ledger
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.contracts c
      WHERE c.id::text = contract_id
        AND c.organization_id = (auth.jwt() ->> 'organization_id')::uuid
    )
  );

-- ── 2. Immutability trigger: block DELETE at Postgres level ─────────────────

CREATE OR REPLACE FUNCTION public.prevent_ledger_v1_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'sla_audit_ledger is immutable (INV-1). DELETE is forbidden. id: %',
    OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_ledger_v1_no_delete ON public.sla_audit_ledger;
CREATE TRIGGER trg_ledger_v1_no_delete
  BEFORE DELETE ON public.sla_audit_ledger
  FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_v1_delete();
