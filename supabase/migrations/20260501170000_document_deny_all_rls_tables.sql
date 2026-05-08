-- Migration: Document intentional deny-all RLS tables
-- These tables have RLS enabled with NO policies, meaning all access is denied
-- for authenticated users. Only service_role (which bypasses RLS) can access them.
-- This is the correct security posture for infrastructure/internal tables.

-- ── Super Admin infrastructure (service_role only) ──────────────────────────
COMMENT ON TABLE public.super_admin_users IS
  'deny-all: Managed exclusively via service_role RPCs. No authenticated user access.';

COMMENT ON TABLE public.super_admin_mfa_lockouts IS
  'deny-all: MFA lockout state. service_role only — security-critical.';

COMMENT ON TABLE public.super_admin_recovery_codes IS
  'deny-all: Recovery codes. service_role only — security-critical.';

-- ── Billing & Quotas (service_role only) ────────────────────────────────────
COMMENT ON TABLE public.tenant_billing_events IS
  'deny-all: Billing events written by service_role triggers. No tenant access.';

-- ── Secrets & Impersonation (service_role only) ─────────────────────────────
COMMENT ON TABLE public.org_api_secrets IS
  'deny-all: HMAC secrets (INV-28). NEVER expose via RLS. service_role only.';

COMMENT ON TABLE public.impersonation_sessions IS
  'deny-all: Impersonation audit trail. service_role only.';

-- ── Background processing (service_role only) ───────────────────────────────
COMMENT ON TABLE public.evidence_deletion_queue IS
  'deny-all: Background cleanup queue. service_role only.';

-- ── Telegram Bot tables (Edge Functions via service_role) ───────────────────
COMMENT ON TABLE public.telegram_binding_tokens IS
  'deny-all: Telegram bot binding tokens. Edge Function (service_role) only.';

COMMENT ON TABLE public.telegram_chat_bindings IS
  'deny-all: Telegram chat-to-driver bindings. Edge Function (service_role) only.';

COMMENT ON TABLE public.telegram_evidence_uploads IS
  'deny-all: Raw evidence uploads from Telegram. Edge Function (service_role) only.';

COMMENT ON TABLE public.telegram_evidence_links IS
  'deny-all: Evidence-to-execution links. Edge Function (service_role) only.';

COMMENT ON TABLE public.telegram_user_consents IS
  'deny-all: LGPD consent records. Edge Function (service_role) only.';

COMMENT ON TABLE public.telegram_evidence_metadata IS
  'deny-all: Evidence metadata (entropy, magic bytes). Edge Function (service_role) only.';

COMMENT ON TABLE public.telegram_evidence_categories IS
  'deny-all: Evidence category mappings. Edge Function (service_role) only.';

-- ── Justification submission (service_role only — anonymous token flow) ─────

-- ── Tables needing evaluation (TODO: decide if tenant SELECT is needed) ─────
-- These are flagged for review — they may need org-scoped SELECT policies.

COMMENT ON TABLE public.contractual_evaluation_traces IS
  'TODO-RLS: Evaluate if tenants need SELECT access to their own explainability traces.';

COMMENT ON TABLE public.sanction_escalation_log IS
  'TODO-RLS: Evaluate if tenant admins need SELECT access to escalation history.';

COMMENT ON TABLE public.justification_audit_logs IS
  'TODO-RLS: Evaluate if tenant admins need SELECT access to justification audit logs.';

