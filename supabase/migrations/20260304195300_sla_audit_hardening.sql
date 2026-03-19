-- ============================================================
-- veraprob — SLA Audit Hardening Migration
-- ============================================================
-- FASE 11: Enforce database-level invariants for the SLA audit domain.
--
-- Invariants enforced:
--   1. sla_audit_ledger is APPEND-ONLY (INSERT + SELECT only)
--   2. contractual_financial_snapshot is IMMUTABLE after creation
--   3. Row Level Security active on all SLA audit tables
-- ============================================================

-- ============================================================
-- PART 1 — REVOKE UPDATE/DELETE ON IMMUTABLE TABLES
-- ============================================================

-- Ledger: append-only. No record may ever be modified or removed.
REVOKE UPDATE, DELETE ON public.sla_audit_ledger
FROM PUBLIC, anon, authenticated;

-- Snapshot: immutable after creation. No snapshot may be altered or removed.
REVOKE UPDATE, DELETE ON public.contractual_financial_snapshot
FROM PUBLIC, anon, authenticated;

-- ============================================================
-- PART 2 — ENABLE ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.sla_audit_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contractual_financial_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.execution_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_declarations ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- PART 3 — ACCESS POLICIES
-- ============================================================

-- Ledger: INSERT + SELECT only (append-only)
CREATE POLICY "Ledger Insert"
ON public.sla_audit_ledger
FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Ledger Read"
ON public.sla_audit_ledger
FOR SELECT
TO authenticated
USING (true);

-- Snapshot: INSERT + SELECT only (immutable)
CREATE POLICY "Snapshot Insert"
ON public.contractual_financial_snapshot
FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Snapshot Read"
ON public.contractual_financial_snapshot
FOR SELECT
TO authenticated
USING (true);

-- Execution State: full CRUD for the application (mutable aggregate)
CREATE POLICY "ExecutionState All"
ON public.execution_states
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- Plan Declarations: INSERT + SELECT (immutable declarations)
CREATE POLICY "PlanDeclaration Insert"
ON public.plan_declarations
FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "PlanDeclaration Read"
ON public.plan_declarations
FOR SELECT
TO authenticated
USING (true);
