BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(5);

SELECT has_function('public', 'schedule_contractual_rule', ARRAY['uuid', 'uuid', 'sla_rule_type', 'jsonb', 'integer', 'timestamp with time zone']);
SELECT has_function('public', 'activate_scheduled_rule', ARRAY['uuid']);
SELECT has_function('public', 'retire_contractual_rule', ARRAY['uuid']);
SELECT has_function('public', 'amend_contract_financial_terms', ARRAY['uuid', 'bigint', 'integer', 'timestamp with time zone', 'text']);

-- The update_contractual_rule is existing, we just modified it. 
SELECT has_function('public', 'update_contractual_rule', ARRAY['uuid', 'uuid', 'sla_rule_type', 'jsonb', 'integer', 'timestamp with time zone']);

SELECT * FROM finish();
ROLLBACK;
