BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(9);

-- 1. Check columns exist
SELECT has_column('public', 'contract_rule_versions', 'is_scheduled', 'is_scheduled column should exist');
SELECT has_column('public', 'contract_rule_versions', 'created_at_utc', 'created_at_utc column should exist');

-- 2. Check defaults
SELECT col_default_is('public', 'contract_rule_versions', 'is_scheduled', 'false', 'is_scheduled defaults to false');

-- 3. Check partial unique indexes
SELECT has_index('public', 'contract_rule_versions', 'idx_unique_current_rule', 'idx_unique_current_rule index should exist');
SELECT has_index('public', 'contract_rule_versions', 'idx_unique_scheduled_rule', 'idx_unique_scheduled_rule index should exist');

-- 4. Check constraint
-- Removed has_table_constraint as it's not a standard pgTAP function

-- 5. Data tests
INSERT INTO public.organizations (
  id, name, status
) VALUES (
  '00000000-0000-0000-0000-000000000001', 'Test Org', 'ACTIVE'
) ON CONFLICT DO NOTHING;
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id) VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'C-123') ON CONFLICT DO NOTHING;

PREPARE test_backdate AS
  INSERT INTO public.contract_rule_versions (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order, active_from_utc, created_at_utc)
  VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000002', 'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 10}', 1, 1, now() - INTERVAL '10 minutes', now());

SELECT throws_ok(
  'test_backdate',
  '23514',
  'new row for relation "contract_rule_versions" violates check constraint "chk_crv_no_backdate"',
  'backdating INSERT direto -> CHECK blocks'
);

-- Insert a scheduled rule
INSERT INTO public.contract_rule_versions (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order, active_from_utc, is_scheduled)
VALUES ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'MAX_EVIDENCE_GAP', '{"max_gap_seconds": 100}', 1, 2, now() + INTERVAL '1 day', true);

PREPARE test_duplicate_scheduled AS
  INSERT INTO public.contract_rule_versions (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order, active_from_utc, is_scheduled)
  VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000002', 'MAX_EVIDENCE_GAP', '{"max_gap_seconds": 200}', 2, 2, now() + INTERVAL '2 days', true);

SELECT throws_ok(
  'test_duplicate_scheduled',
  '23505',
  'duplicate key value violates unique constraint "idx_unique_scheduled_rule"',
  '2 agendadas mesmo tipo -> unique violation'
);

-- Another test to be safe for current rule
INSERT INTO public.contract_rule_versions (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order, active_from_utc, is_scheduled)
VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000002', 'MIN_GEOFENCE_COVERAGE', '{"min_dwell_seconds": 90}', 1, 3, now(), false);

PREPARE test_duplicate_current AS
  INSERT INTO public.contract_rule_versions (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order, active_from_utc, is_scheduled)
  VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000002', 'MIN_GEOFENCE_COVERAGE', '{"min_dwell_seconds": 95}', 2, 3, now(), false);

SELECT throws_ok(
  'test_duplicate_current',
  '23505',
  'duplicate key value violates unique constraint "idx_unique_current_rule"',
  '2 current rules mesmo tipo -> unique violation'
);

-- Ensure old index is dropped
SELECT hasnt_index('public', 'contract_rule_versions', 'idx_unique_active_rule_type', 'old index should be dropped');

SELECT * FROM finish();
ROLLBACK;
