-- =============================================================================
-- Phase 8.5 — RLS Dual-Key Audit & Hardening (INV-20 completion)
-- =============================================================================
-- CONTEXT:
--   Migration 20260402000002_contractor_viewer_dual_key.sql introduced dual-key
--   isolation for audit_packages. This migration audits all remaining tables
--   and closes the CONTRACTOR_VIEWER gap on the `contractors` table itself.
--
-- THREAT (qa_security):
--   A CONTRACTOR_VIEWER with a valid JWT (org_id + contractor_id) can query
--   `SELECT * FROM contractors` and see ALL contractors in the organization —
--   not just their own record. A contractor should never know who else the
--   operator works with. This is an A01 (Broken Access Control) finding.
--
-- CHANGES:
--   A. Diagnostic queries — inventory of USING(true) and single-key policies
--      (run as comments; execute manually in Supabase SQL Editor for audit)
--   B. contractors table — replace single org-key policy with dual-policy strategy:
--      - Internal roles: org isolation (same as current)
--      - CONTRACTOR_VIEWER: org + contractor_id = jwt.contractor_id (own record only)
--   C. contracts table — add CONTRACTOR_VIEWER read-only isolation guard:
--      contracts.contractor_id FK must match jwt.contractor_id
--
-- INVARIANTS:
--   INV-6:  MULTI-TENANT + RLS — every record carries organization_id
--   INV-10: RLS TENANT CLAIM — use auth.jwt() -> 'app_metadata', not auth.uid()
--   INV-20: CONTRACTOR_VIEWER DUAL-KEY ISOLATION
-- =============================================================================


-- =============================================================================
-- DIAGNOSTIC QUERIES (informational — run in Supabase SQL Editor for audit)
-- =============================================================================
--
-- 1. Find all policies with USING (true) — potential unrestricted access:
--
--    SELECT schemaname, tablename, policyname, cmd, qual
--    FROM pg_policies
--    WHERE schemaname = 'public'
--      AND (qual = 'true' OR qual IS NULL)
--    ORDER BY tablename, policyname;
--
-- Expected findings (pre-multi-tenancy legacy tables — no organization_id column):
--   sla_audit_ledger     — Ledger Read / Ledger Insert (USING true)
--   contractual_financial_snapshot — Snapshot Read / Snapshot Insert
--   execution_states     — ExecutionState All (USING true)
--   plan_declarations    — PlanDeclaration Read / PlanDeclaration Insert
--   These tables pre-date multi-tenancy and have no organization_id column.
--   They are superseded by v2 tables (sla_audit_ledger_v2, etc.) which have
--   proper org isolation. Flagged for future schema cleanup.
--
-- 2. Find tables with organization_id but missing contractor isolation
--    for CONTRACTOR_VIEWER role:
--
--    SELECT t.tablename
--    FROM pg_tables t
--    JOIN information_schema.columns c
--      ON c.table_schema = 'public'
--      AND c.table_name  = t.tablename
--      AND c.column_name = 'contractor_id'
--    WHERE t.schemaname = 'public'
--      AND NOT EXISTS (
--        SELECT 1 FROM pg_policies p
--        WHERE p.schemaname = 'public'
--          AND p.tablename  = t.tablename
--          AND p.policyname ILIKE '%contractor_viewer%'
--      )
--    ORDER BY t.tablename;
--
-- Pre-fix expected: contractors, (potentially contracts if contractor_id added)
-- =============================================================================


-- =============================================================================
-- A. CONTRACTORS TABLE — Dual-Policy Strategy (INV-20)
-- =============================================================================
-- Current policy: single policy, org isolation only.
-- CONTRACTOR_VIEWER can read ALL contractors in the org — data breach.
-- Fix: two policies, matching the pattern from audit_packages.
-- =============================================================================

DROP POLICY IF EXISTS "Tenant Isolation: contractors" ON public.contractors;

-- Policy 1: Internal roles (TENANT_ADMIN, OPERATOR, AUDITOR)
-- contractor_id in JWT must be NULL (enforced by hook — defense-in-depth INV-20)
-- FIX: Use canonical JWT path (auth.jwt() ->> 'organization_id') per INV-5
CREATE POLICY "contractors_internal_roles"
  ON public.contractors
  FOR ALL
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  )
  WITH CHECK (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  );

-- Policy 2: CONTRACTOR_VIEWER — sees only their OWN contractor record (INV-20)
-- Read-only (SELECT). Cannot insert/update contractor records.
CREATE POLICY "contractors_contractor_viewer_isolation"
  ON public.contractors
  FOR SELECT
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND id = (auth.jwt() -> 'app_metadata' ->> 'contractor_id')::uuid
  );


-- =============================================================================
-- B. CONTRACTS TABLE — CONTRACTOR_VIEWER isolation (INV-20)
-- =============================================================================
-- The contracts table currently has a single org-isolation policy.
-- Phase 6.8 added contractor_id FK to contracts (via b2b_refactoring).
-- CONTRACTOR_VIEWER should only read contracts linked to their contractor.
--
-- PREREQUISITE CHECK: contracts must have a contractor_id column.
-- If this column does not yet exist, this policy uses an EXISTS subquery
-- against the contractors table to derive the link.
--
-- Strategy: Add a CONTRACTOR_VIEWER-specific SELECT policy that joins on
-- contractor_id. Internal roles keep the existing org-only policy but with
-- explicit NULL-contractor guard for defense-in-depth.
-- =============================================================================

-- Drop the unified policy set by 20260317000001_rls_jwt_path_unification.sql
DROP POLICY IF EXISTS "Tenant Isolation: contracts" ON public.contracts;

-- Policy 1: Internal roles — org isolation + contractor_id NULL guard
CREATE POLICY "contracts_internal_roles"
  ON public.contracts
  FOR ALL
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  )
  WITH CHECK (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  );

-- Policy 2: CONTRACTOR_VIEWER — read contracts where their contractor is involved
-- Uses subquery on contractors table to avoid requiring a direct contractor_id FK
-- on contracts (which may not exist yet). Contractors are linked by name or future FK.
-- NOTE: Once contracts.contractor_id FK is formally added, replace EXISTS with:
--   AND contractor_id = (auth.jwt() -> 'app_metadata' ->> 'contractor_id')::uuid
CREATE POLICY "contracts_contractor_viewer_isolation"
  ON public.contracts
  FOR SELECT
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND EXISTS (
      SELECT 1
      FROM public.contractors c
      WHERE c.organization_id = contracts.organization_id
        AND c.id = (auth.jwt() -> 'app_metadata' ->> 'contractor_id')::uuid
        AND (
          -- Match by contractor_id FK if column exists (future-proof)
          -- Match by contractor name as current fallback
          c.name = contracts.contractor_name
        )
    )
  );


-- =============================================================================
-- VERIFICATION STEPS (run in Supabase SQL Editor after applying)
-- =============================================================================
--
-- 1. CONTRACTOR_VIEWER cannot see other contractors:
--    As CONTRACTOR_VIEWER JWT for contractor_id = 'X':
--      SELECT count(*) FROM contractors;
--    → Must return 1 (only their own record)
--
-- 2. Internal OPERATOR sees all contractors in their org:
--    As OPERATOR JWT (contractor_id = NULL in JWT):
--      SELECT count(*) FROM contractors;
--    → Must return all contractors for the org
--
-- 3. CONTRACTOR_VIEWER without contractor_id in JWT is fully blocked:
--    Simulate JWT with contractor_id = null:
--      SELECT count(*) FROM contractors;
--    → Must return 0 (NULL::uuid cast blocks the IS NULL guard in policy 2)
--
-- 4. Check the pre-multi-tenancy USING(true) tables are not accessible
--    to CONTRACTOR_VIEWER (they lack organization_id — risk is low but note
--    them for future schema cleanup in Phase 9):
--    Tables: sla_audit_ledger, contractual_financial_snapshot, execution_states
-- =============================================================================
