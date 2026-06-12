BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(10);

-- =============================================================================
-- pgTAP: deterministic least-privilege grants on read-only public views
-- Migration: 20260815000002_normalize_view_grants_least_privilege.sql
-- Focus: service_role pinned to SELECT-only on the 3 read-only views; anon never
-- reads PII/summary views; authenticated keeps SELECT.
-- =============================================================================

-- ── service_role: SELECT only (least privilege, deterministic) ───────────────
SELECT table_privs_are('public', 'contractors_view', 'service_role',
  ARRAY['SELECT'], 'V1: service_role SELECT-only on contractors_view');
SELECT table_privs_are('public', 'invitations_view', 'service_role',
  ARRAY['SELECT'], 'V2: service_role SELECT-only on invitations_view');
SELECT table_privs_are('public', 'v_roi_summary', 'service_role',
  ARRAY['SELECT'], 'V3: service_role SELECT-only on v_roi_summary');

-- ── authenticated keeps SELECT ───────────────────────────────────────────────
SELECT table_privs_are('public', 'contractors_view', 'authenticated',
  ARRAY['SELECT'], 'V4: authenticated SELECT on contractors_view');

-- ── anon never reads PII / summary views (INV-22) ────────────────────────────
SELECT table_privs_are('public', 'contractors_view', 'anon',
  ARRAY[]::text[], 'V5: anon no privileges on contractors_view');
SELECT table_privs_are('public', 'invitations_view', 'anon',
  ARRAY[]::text[], 'V6: anon no privileges on invitations_view');
SELECT table_privs_are('public', 'v_roi_summary', 'anon',
  ARRAY[]::text[], 'V7: anon no privileges on v_roi_summary');

-- ── vw_device_heartbeat_status: backend-only read view ───────────────────────
SELECT table_privs_are('public', 'vw_device_heartbeat_status', 'service_role',
  ARRAY['SELECT'], 'V8: service_role SELECT-only on vw_device_heartbeat_status');
SELECT table_privs_are('public', 'vw_device_heartbeat_status', 'authenticated',
  ARRAY[]::text[], 'V9: authenticated no privileges on vw_device_heartbeat_status');
SELECT table_privs_are('public', 'vw_device_heartbeat_status', 'anon',
  ARRAY[]::text[], 'V10: anon no privileges on vw_device_heartbeat_status');

SELECT * FROM finish();
ROLLBACK;
