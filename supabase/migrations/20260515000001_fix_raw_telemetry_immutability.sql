-- =============================================================================
-- Migration: Fix raw_telemetry_payloads immutability (rule → trigger)
--
-- Root cause: DO INSTEAD NOTHING rules are incompatible with PostgREST's
-- automatic RETURNING * clause (PostgreSQL error 0A000 feature_not_supported).
-- Replace with GUC-aware triggers using the existing prevent_immutable_update()
-- function (defined in 20260423180000_forensic_test_hardening.sql).
--
-- INV-3: append-only guarantee is preserved; enforcement moves from rule-layer
-- to trigger-layer which PostgREST handles correctly (raises restrict_violation,
-- returned as HTTP 409 to the caller rather than a 500 crash).
--
-- Also adds test_tamper_raw_telemetry_payload — a SECURITY DEFINER RPC for
-- red-team tests that must simulate a DBA-level tamper (bypass all guards) to
-- validate that the application's hash-verification layer (INV-9) detects it.
-- The GUC approach (SET LOCAL) keeps the bypass TX-scoped and lock-free.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Drop incompatible DO INSTEAD NOTHING rules ────────────────────────────

DROP RULE IF EXISTS raw_telemetry_payloads_no_update ON public.raw_telemetry_payloads;
DROP RULE IF EXISTS raw_telemetry_payloads_no_delete ON public.raw_telemetry_payloads;

-- ── 2. Trigger-based immutability (PostgREST-compatible, GUC-aware) ──────────
--
-- prevent_immutable_update() checks vera.authorized_test_cleanup GUC:
--   'on'  → allows the operation (test-only maintenance window)
--   other → raises restrict_violation (INV-3 enforcement)

DROP TRIGGER IF EXISTS trg_raw_telemetry_no_update ON public.raw_telemetry_payloads;
CREATE TRIGGER trg_raw_telemetry_no_update
  BEFORE UPDATE ON public.raw_telemetry_payloads
  FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_update();

DROP TRIGGER IF EXISTS trg_raw_telemetry_no_delete ON public.raw_telemetry_payloads;
CREATE TRIGGER trg_raw_telemetry_no_delete
  BEFORE DELETE ON public.raw_telemetry_payloads
  FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_update();

-- ── 3. Red-team tamper RPC (test-only, service_role-gated) ───────────────────
--
-- Simulates a malicious DBA modifying raw_payload WITHOUT updating payload_hash.
-- Used by hmac_tampering_detection_test.dart (Phase 2) to prove the app-layer
-- hash verification (INV-9 / INV-31) detects the tamper and raises IntegrityException.
--
-- Security: SECURITY DEFINER + REVOKE from PUBLIC + GRANT to service_role only.
-- The GUC is SET LOCAL (TX-scoped) — no risk of GUC leaking across connections.

CREATE OR REPLACE FUNCTION public.test_tamper_raw_telemetry_payload(
  p_record_id UUID,
  p_new_payload JSONB
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  SET LOCAL vera.authorized_test_cleanup = 'on'; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  UPDATE public.raw_telemetry_payloads
  SET raw_payload = p_new_payload
  WHERE id = p_record_id;
END;
$$;

REVOKE ALL ON FUNCTION public.test_tamper_raw_telemetry_payload(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.test_tamper_raw_telemetry_payload(UUID, JSONB) TO service_role;
