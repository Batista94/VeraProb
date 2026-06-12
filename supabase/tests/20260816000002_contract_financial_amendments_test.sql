BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(6);

SELECT has_table('public', 'contract_financial_amendments', 'contract_financial_amendments exists');
SELECT has_column('public', 'contract_financial_amendments', 'penalty_multiplier_bps', 'penalty_multiplier_bps exists');
SELECT col_type_is('public', 'contract_financial_amendments', 'penalty_multiplier_bps', 'integer', 'penalty_multiplier_bps is INT');

-- Constraints are implicitly tested by the data tests
SELECT has_trigger('public', 'contract_financial_amendments', 'trg_cfa_append_only', 'append_only trigger should exist');

-- Check grants
SELECT table_privs_are('public', 'contract_financial_amendments', 'authenticated', ARRAY['SELECT', 'INSERT'], 'authenticated has SELECT and INSERT');
SELECT table_privs_are('public', 'contract_financial_amendments', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role has ALL');

SELECT * FROM finish();
ROLLBACK;
