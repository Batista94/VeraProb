-- pr_scanner: ignore-regression
-- pr_scanner: ignore-rls (intentional: admin-role based access, not org isolation)
-- =============================================================================
-- 8.4 Observabilidade — System Audit Log
-- Migration: 20260403000001_system_audit_log.sql
-- =============================================================================
-- Append-only log table for system-level events (errors, security events,
-- engine lifecycle). NOT for tenant business data.
--
-- INV-1 compliance: NO UPDATE or DELETE — facts are permanent.
-- RLS: INSERT is open (internal infra write path).
--      SELECT restricted to admin role only.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.system_audit_log (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type    TEXT        NOT NULL,
  severity      TEXT        NOT NULL DEFAULT 'info'
    CHECK (severity IN ('debug', 'info', 'warning', 'error', 'critical')),
  payload       JSONB,
  source        TEXT,  -- e.g., 'flutter_web', 'edge_function', 'evaluation_engine'
  occurred_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()  -- UTC, always
);

-- Immutability guard: prevent any UPDATE or DELETE at DB level (INV-1)
CREATE OR REPLACE RULE system_audit_log_no_update AS
  ON UPDATE TO public.system_audit_log DO INSTEAD NOTHING;

CREATE OR REPLACE RULE system_audit_log_no_delete AS
  ON DELETE TO public.system_audit_log DO INSTEAD NOTHING;

-- Performance index: query by event_type + time window
CREATE INDEX IF NOT EXISTS idx_system_audit_log_type_time
  ON public.system_audit_log (event_type, occurred_at DESC);

-- Performance index: query by severity for alerting
CREATE INDEX IF NOT EXISTS idx_system_audit_log_severity
  ON public.system_audit_log (severity, occurred_at DESC)
  WHERE severity IN ('error', 'critical');

-- =============================================================================
-- Row Level Security
-- =============================================================================
ALTER TABLE public.system_audit_log ENABLE ROW LEVEL SECURITY;

-- INSERT: allowed for authenticated users (internal infra writes from edge functions)
-- Note: service_role bypasses RLS automatically. Dart client uses anon/auth key.
CREATE POLICY system_audit_log_insert_policy ON public.system_audit_log
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- SELECT: only users with role 'admin' may read system logs
-- Admin role is identified by the JWT claim 'role' = 'admin'
-- Non-admin tenants must never see system-level logs.
CREATE POLICY system_audit_log_select_admin_policy ON public.system_audit_log
  FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'user_role') = 'admin'
  );

-- =============================================================================
-- VALIDATION (run EXPLAIN to confirm index usage)
-- =============================================================================
-- EXPLAIN SELECT * FROM system_audit_log
--   WHERE event_type = 'sentry_error'
--   AND occurred_at > NOW() - INTERVAL '24 hours'
--   ORDER BY occurred_at DESC
--   LIMIT 100;
-- Expected: Index Scan on idx_system_audit_log_type_time
