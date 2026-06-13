-- pr_scanner: ignore-regression
-- Council-reviewed (Sprint B SLA Versioning plan, approved 2026-06-12).
-- =============================================================================
-- Fix: revoke EXECUTE on test helpers from authenticated (A3 / A3b regression)
-- =============================================================================
BEGIN;
REVOKE EXECUTE ON FUNCTION public.test_cleanup_forensic_data(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.test_tamper_raw_telemetry_payload(uuid, jsonb) FROM PUBLIC, anon, authenticated;
COMMIT;
