BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(30);

-- =============================================================================
-- pgTAP: restore EXECUTE grants stripped by 20260717000002 (REVOKE FROM PUBLIC)
-- Migration: 20260815000001_restore_execute_grants_revoke_regression.sql
-- Focus: trusted roles regain EXECUTE on super_admin_* / invitation / test
-- helpers; anon stays revoked; Phase 10.6 dispute RPCs stay service_role-locked.
-- =============================================================================

-- ── super_admin_* family: service_role EXECUTE (E2E bootstrap path) ──────────
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_create_organization(text, text, text, text, text, text, integer, integer, uuid, jsonb, integer, integer, integer, text, text, text, text, text[])',
  'EXECUTE'), 'G2: service_role EXECUTE super_admin_create_organization');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_archive_organization(uuid, text, uuid)', 'EXECUTE'),
  'G4: service_role EXECUTE super_admin_archive_organization');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_unarchive_organization(uuid, text, uuid)', 'EXECUTE'),
  'G6a: service_role EXECUTE super_admin_unarchive_organization');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_update_organization_quota(uuid, text, integer, integer, uuid, text, jsonb, bigint, integer, smallint, text, text, text, text, text, timestamp with time zone)',
  'EXECUTE'), 'G6b: service_role EXECUTE super_admin_update_organization_quota');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_add_org_admin(uuid, text, uuid, uuid, timestamp with time zone, uuid)',
  'EXECUTE'), 'G6c: service_role EXECUTE super_admin_add_org_admin/6');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_add_org_admin(uuid, text, uuid, uuid, timestamp with time zone, uuid, text)',
  'EXECUTE'), 'G6d: service_role EXECUTE super_admin_add_org_admin/7');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_invite_first_admin(uuid, text, text, text, uuid, timestamp with time zone, uuid)',
  'EXECUTE'), 'G6e: service_role EXECUTE super_admin_invite_first_admin');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_get_org_members(uuid)', 'EXECUTE'),
  'G6f: service_role EXECUTE super_admin_get_org_members');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_check_cnpj_exists(text)', 'EXECUTE'),
  'G6g: service_role EXECUTE super_admin_check_cnpj_exists');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_revoke_invitation(uuid, text, uuid, text)', 'EXECUTE'),
  'G6h: service_role EXECUTE super_admin_revoke_invitation');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_toggle_member_status(uuid, uuid, boolean)', 'EXECUTE'),
  'G6i: service_role EXECUTE super_admin_toggle_member_status');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_update_allowed_domains(uuid, text[], uuid, text)', 'EXECUTE'),
  'G6j: service_role EXECUTE super_admin_update_allowed_domains');
SELECT ok(has_function_privilege('service_role',
  'public.super_admin_audit_resend_invitation(uuid, text, text)', 'EXECUTE'),
  'G6k: service_role EXECUTE super_admin_audit_resend_invitation');

-- ── authenticated app path (create + archive UI) ─────────────────────────────
SELECT ok(has_function_privilege('authenticated',
  'public.super_admin_create_organization(text, text, text, text, text, text, integer, integer, uuid, jsonb, integer, integer, integer, text, text, text, text, text[])',
  'EXECUTE'), 'G1: authenticated EXECUTE super_admin_create_organization');
SELECT ok(has_function_privilege('authenticated',
  'public.super_admin_archive_organization(uuid, text, uuid)', 'EXECUTE'),
  'G3: authenticated EXECUTE super_admin_archive_organization (was owner-only)');

-- ── token-driven flows: service_role harness ─────────────────────────────────
SELECT ok(has_function_privilege('service_role',
  'public.accept_invitation(text, uuid)', 'EXECUTE'),
  'G5: service_role EXECUTE accept_invitation (coverage-gate race harness)');
SELECT ok(has_function_privilege('service_role',
  'public.accept_contract_by_contractor(text)', 'EXECUTE'),
  'G5b: service_role EXECUTE accept_contract_by_contractor');
SELECT ok(has_function_privilege('service_role',
  'public.get_contract_for_review(text)', 'EXECUTE'),
  'G5c: service_role EXECUTE get_contract_for_review');

-- ── E2E/CI helpers: service_role ─────────────────────────────────────────────
SELECT ok(has_function_privilege('service_role',
  'public.test_archive_org_for_e2e(uuid)', 'EXECUTE'),
  'G7a: service_role EXECUTE test_archive_org_for_e2e');
SELECT ok(has_function_privilege('service_role',
  'public.test_cleanup_forensic_data(uuid)', 'EXECUTE'),
  'G7b: service_role EXECUTE test_cleanup_forensic_data');
SELECT ok(has_function_privilege('service_role',
  'public.test_cleanup_system_audit_log(uuid[])', 'EXECUTE'),
  'G7c: service_role EXECUTE test_cleanup_system_audit_log');
SELECT ok(has_function_privilege('service_role',
  'public.test_get_user_banned_until(uuid)', 'EXECUTE'),
  'G7d: service_role EXECUTE test_get_user_banned_until');
SELECT ok(has_function_privilege('service_role',
  'public.test_tamper_raw_telemetry_payload(uuid, jsonb)', 'EXECUTE'),
  'G7e: service_role EXECUTE test_tamper_raw_telemetry_payload');

-- ── anon stays revoked (INV-2) ───────────────────────────────────────────────
SELECT ok(NOT has_function_privilege('anon',
  'public.super_admin_create_organization(text, text, text, text, text, text, integer, integer, uuid, jsonb, integer, integer, integer, text, text, text, text, text[])',
  'EXECUTE'), 'A1: anon CANNOT EXECUTE super_admin_create_organization');
SELECT ok(NOT has_function_privilege('anon',
  'public.super_admin_archive_organization(uuid, text, uuid)', 'EXECUTE'),
  'A2: anon CANNOT EXECUTE super_admin_archive_organization');
SELECT ok(NOT has_function_privilege('anon',
  'public.test_cleanup_forensic_data(uuid)', 'EXECUTE'),
  'A2b: anon CANNOT EXECUTE test_cleanup_forensic_data');

-- ── test_* helpers never reachable by ordinary tenant users (prod safety) ────
SELECT ok(NOT has_function_privilege('authenticated',
  'public.test_cleanup_forensic_data(uuid)', 'EXECUTE'),
  'A3: authenticated CANNOT EXECUTE test_cleanup_forensic_data');
SELECT ok(NOT has_function_privilege('authenticated',
  'public.test_tamper_raw_telemetry_payload(uuid, jsonb)', 'EXECUTE'),
  'A3b: authenticated CANNOT EXECUTE test_tamper_raw_telemetry_payload');

-- ── Phase 10.6 dispute RPCs stay service_role-locked (anti-regression) ───────
SELECT ok(NOT has_function_privilege('service_role',
  'public.resolve_dispute(uuid, uuid, text, text, uuid, text, timestamp with time zone, text, text)',
  'EXECUTE'), 'R1: service_role still CANNOT EXECUTE resolve_dispute (10.6 lock)');
SELECT ok(NOT has_function_privilege('service_role',
  'public.attach_dispute_evidence(uuid, uuid, text, text, text, bigint, text, uuid, timestamp with time zone)',
  'EXECUTE'), 'R2: service_role still CANNOT EXECUTE attach_dispute_evidence (10.6 lock)');

SELECT * FROM finish();
ROLLBACK;
