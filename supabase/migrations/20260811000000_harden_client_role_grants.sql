-- =============================================================================
-- Migration: Harden Data API role grants — revoke the legacy ALTER DEFAULT
--            PRIVILEGES `arwdDxtm` surface from anon / authenticated.
--
-- ADVISOR / FORENSIC FINDING (CIA sweep 2026-06-09):
-- The legacy Supabase `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ...`
-- (grantor: postgres) auto-grants INSERT/SELECT/UPDATE/DELETE/TRUNCATE/REFERENCES/
-- TRIGGER/MAINTAIN to `anon` and `authenticated` on every table created by
-- `postgres`. Per-table hardening was applied only partially, leaving the most
-- sensitive tables exposed:
--   - anon (UNAUTHENTICATED) held TRUNCATE on 30 tables incl. contracts, vehicles,
--     the append-only SLA ledger (sla_audit_ledger_v2 + partitions) and
--     forensic_evidence_snapshots.
--   - authenticated (ANY tenant user) held TRUNCATE on the ledger partitions and
--     evidence snapshots, and DELETE/UPDATE on the ledger.
--
-- WHY THIS IS CRITICAL: RLS policies DO NOT apply to TRUNCATE. An extracted anon
-- key could `TRUNCATE public.sla_audit_ledger_v2` / `TRUNCATE public.contracts`
-- and destroy every tenant's data and the immutable forensic ledger. Any logged-in
-- Tenant-A user could TRUNCATE evidence/ledger and wipe Tenant-B's records.
-- Violates INV-3 (append-only ledger), INV-22 (tenant isolation), availability.
--
-- All affected tables are owned by (and granted by) `postgres`, so these REVOKEs
-- are executable at the migration tier and WILL take effect (verified: grantor =
-- postgres on every grant — unlike the supabase_admin-owned spatial_ref_sys case).
--
-- This migration also pins the search_path of two SECURITY DEFINER functions
-- flagged by the `function_search_path_mutable` advisor (CWE-426).
--
-- Idempotent: REVOKE of an absent privilege is a no-op; ALTER FUNCTION ... SET is
-- last-write-wins. Safe to re-run via `supabase db push`.
--
-- NOTE on INV-DB annotations: the `REVOKE ... TRUNCATE/DELETE/UPDATE` statements
-- below are PRIVILEGE revocations (instant catalog metadata, no table scan, no data
-- loss) — NOT destructive DML/DDL. The scanner pattern-matches the TRUNCATE/DELETE
-- keywords, so each is annotated `-- INV-DB: zero-downtime-verified`. Requires
-- Council (QA/Security) ack on review, per the Regression-Ack discipline.
--
-- Invariants: INV-2, INV-3, INV-22, INV-DATA-API-GRANT (CI block #13).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── (1) Stop the bleed: future tables must not inherit the insecure default ──
-- postgres can only alter its OWN default privileges; app tables are created by
-- postgres (migrations run as postgres), so this covers all future app tables.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM authenticated; -- INV-DB: zero-downtime-verified (default-privilege REVOKE, not DML)

-- ── (2) Universal: no client role may TRUNCATE any public table ──────────────
-- RLS never gates TRUNCATE — this is the primary CRITICAL closure.
REVOKE TRUNCATE ON ALL TABLES IN SCHEMA public FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)

-- ── (3) Append-only forensic ledger + evidence: never UPDATE/DELETE/TRUNCATE ──
-- Client roles keep only SELECT/INSERT (writes flow through SECURITY DEFINER RPCs
-- owned by postgres). INV-3 immutability enforced at the grant layer.
REVOKE UPDATE, DELETE, TRUNCATE ON public.sla_audit_ledger_v2 FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE UPDATE, DELETE, TRUNCATE ON public.sla_audit_ledger_p0 FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE UPDATE, DELETE, TRUNCATE ON public.sla_audit_ledger_p1 FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE UPDATE, DELETE, TRUNCATE ON public.sla_audit_ledger_p2 FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE UPDATE, DELETE, TRUNCATE ON public.sla_audit_ledger_p3 FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE UPDATE, DELETE, TRUNCATE ON public.forensic_evidence_snapshots FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)

-- ── (4) anon defense-in-depth: strip ALL on tenant/business tables ───────────
-- None of these have an anon RLS policy, so RLS already denies anon every row;
-- removing the dead grants eliminates the residual TRUNCATE/REFERENCES surface and
-- shrinks the Data API attack surface. Public-flow token tables
-- (contract_review_tokens, justification_submission_tokens, telegram_binding_tokens)
-- and the RLS-gated telegram_* tables are intentionally left untouched.
REVOKE ALL ON
  public.contracts,
  public.contractors,
  public.vehicles,
  public.execution_states,
  public.contractual_service_executions,
  public.contractual_financial_snapshot,
  public.operational_zones,
  public.operational_alerts,
  public.routes,
  public.plan_declarations,
  public.service_manifests,
  public.contract_rule_sets,
  public.contract_rule_versions,
  public.contractor_justifications,
  public.justification_evidence_uploads,
  public.sanction_review_queue,
  public.forensic_evidence_snapshots,
  public.sla_audit_ledger_v2,
  public.sla_audit_ledger_p0,
  public.sla_audit_ledger_p1,
  public.sla_audit_ledger_p2,
  public.sla_audit_ledger_p3
  FROM anon; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)

-- ── (5) Pin search_path on SECURITY DEFINER functions (CWE-426) ──────────────
-- Metadata-only; bodies unchanged → preserves INV-15 replay determinism.
ALTER FUNCTION public.auto_enqueue_sanction_recommended() SET search_path = public;
ALTER FUNCTION public.create_execution_for_operator(
  uuid, text, uuid, uuid, uuid, uuid, timestamptz, timestamptz
) SET search_path = public;
