-- =============================================================================
-- pgTAP: Tenant RBAC permission helpers (Pilar 1.3) — migration 20260909000003
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

SELECT has_function('public', 'has_permission', ARRAY['text']);
SELECT has_function('public', 'has_permission_on', ARRAY['text', 'uuid']);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009a2","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"OPERATOR","permissions":["financial:read","telemetry:read"],"perm_scopes":{}}}';

SELECT ok(public.has_permission('financial:read'), 'has_permission true for held key');
SELECT ok(NOT public.has_permission('sla:approve'), 'has_permission false for absent key');
SELECT ok(public.has_permission_on('financial:read', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'has_permission_on true when no scope entry (unrestricted)');

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009a2","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"OPERATOR","permissions":["contracts:read"],"perm_scopes":{"contracts:read":["bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"]}}}';

SELECT ok(
  public.has_permission_on('contracts:read', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'has_permission_on true when resource in scope allowlist');

SELECT ok(
  NOT public.has_permission_on('contracts:read', 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  'has_permission_on false when resource outside scope');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
