-- ============================================================
-- veraprob — Partition RLS Hardening (INV-2, INV-22, INV-DB)
-- ============================================================
-- REASON:
--   PostgreSQL's RLS inheritance model does NOT propagate parent
--   table policies to individual partitions when a client queries
--   a partition directly by name. The four HASH partitions of
--   sla_audit_ledger_v2 (p0–p3) had rowsecurity = false, creating
--   a complete INV-22 (tenant isolation) bypass: any authenticated
--   user could query sla_audit_ledger_p0..p3 directly and receive
--   all tenants' ledger entries unfiltered.
--
--   spatial_ref_sys (PostGIS extension table) also lacked RLS,
--   breaking the "all public-schema tables have RLS" audit invariant.
--
-- SECURITY INVARIANTS:
--   INV-2  — RLS: auth.jwt() -> 'app_metadata' ->> 'org_id'. NO auth.uid()
--   INV-22 — Tenant-A NEVER sees Tenant-B data. Red-Team tested.
--   INV-DB — Non-destructive DDL only. No blocking ALTER/DROP/DELETE.
--
-- EXPLOIT PATH CLOSED:
--   Direct partition query bypass → closed by ENABLE ROW LEVEL SECURITY
--   + FOR ALL policy mirroring the parent on every partition table.
-- ============================================================

-- ── sla_audit_ledger_p0 ──────────────────────────────────────
ALTER TABLE public.sla_audit_ledger_p0 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant Isolation: sla_audit_ledger_p0" ON public.sla_audit_ledger_p0;
CREATE POLICY "Tenant Isolation: sla_audit_ledger_p0"
  ON public.sla_audit_ledger_p0
  FOR ALL
  USING (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID))
  WITH CHECK (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID));

-- ── sla_audit_ledger_p1 ──────────────────────────────────────
ALTER TABLE public.sla_audit_ledger_p1 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant Isolation: sla_audit_ledger_p1" ON public.sla_audit_ledger_p1;
CREATE POLICY "Tenant Isolation: sla_audit_ledger_p1"
  ON public.sla_audit_ledger_p1
  FOR ALL
  USING (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID))
  WITH CHECK (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID));

-- ── sla_audit_ledger_p2 ──────────────────────────────────────
ALTER TABLE public.sla_audit_ledger_p2 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant Isolation: sla_audit_ledger_p2" ON public.sla_audit_ledger_p2;
CREATE POLICY "Tenant Isolation: sla_audit_ledger_p2"
  ON public.sla_audit_ledger_p2
  FOR ALL
  USING (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID))
  WITH CHECK (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID));

-- ── sla_audit_ledger_p3 ──────────────────────────────────────
ALTER TABLE public.sla_audit_ledger_p3 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant Isolation: sla_audit_ledger_p3" ON public.sla_audit_ledger_p3;
CREATE POLICY "Tenant Isolation: sla_audit_ledger_p3"
  ON public.sla_audit_ledger_p3
  FOR ALL
  USING (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID))
  WITH CHECK (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID));

-- ── spatial_ref_sys ───────────────────────────────────────────
-- PostGIS extension table owned by supabase_admin.
-- Cannot ALTER TABLE (permission denied for non-owner).
-- Supabase dashboard alert for this table is a false positive:
-- extension-managed tables are outside application RLS scope.
-- No action required — read-only static SRID reference data.
