BEGIN;

-- Load pgTAP
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Test planning
-- 22 tables * 2 assertions (one for authenticated, one for service_role) = 44 tests
SELECT plan(44);

-- 1. contracts
SELECT table_privs_are('public', 'contracts', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on contracts');
SELECT table_privs_are('public', 'contracts', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contracts');

-- 2. contractors
SELECT table_privs_are('public', 'contractors', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on contractors');
SELECT table_privs_are('public', 'contractors', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contractors');

-- 3. vehicles
SELECT table_privs_are('public', 'vehicles', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on vehicles');
SELECT table_privs_are('public', 'vehicles', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on vehicles');

-- 4. routes
SELECT table_privs_are('public', 'routes', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on routes');
SELECT table_privs_are('public', 'routes', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on routes');

-- 5. operational_zones
SELECT table_privs_are('public', 'operational_zones', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on operational_zones');
SELECT table_privs_are('public', 'operational_zones', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on operational_zones');

-- 6. plan_declarations
SELECT table_privs_are('public', 'plan_declarations', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on plan_declarations');
SELECT table_privs_are('public', 'plan_declarations', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on plan_declarations');

-- 7. contractual_service_executions
SELECT table_privs_are('public', 'contractual_service_executions', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on contractual_service_executions');
SELECT table_privs_are('public', 'contractual_service_executions', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contractual_service_executions');

-- 8. execution_states
SELECT table_privs_are('public', 'execution_states', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on execution_states');
SELECT table_privs_are('public', 'execution_states', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on execution_states');

-- 9. sanction_review_queue
SELECT table_privs_are('public', 'sanction_review_queue', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on sanction_review_queue');
SELECT table_privs_are('public', 'sanction_review_queue', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on sanction_review_queue');

-- 10. operational_alerts
SELECT table_privs_are('public', 'operational_alerts', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on operational_alerts');
SELECT table_privs_are('public', 'operational_alerts', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on operational_alerts');

-- 11. contractual_financial_snapshot
SELECT table_privs_are('public', 'contractual_financial_snapshot', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on contractual_financial_snapshot');
SELECT table_privs_are('public', 'contractual_financial_snapshot', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contractual_financial_snapshot');

-- 12. sla_audit_ledger_v2
SELECT table_privs_are('public', 'sla_audit_ledger_v2', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on sla_audit_ledger_v2');
SELECT table_privs_are('public', 'sla_audit_ledger_v2', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on sla_audit_ledger_v2');

-- 13. service_manifests
SELECT table_privs_are('public', 'service_manifests', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on service_manifests');
SELECT table_privs_are('public', 'service_manifests', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on service_manifests');

-- 14. contract_rule_sets
SELECT table_privs_are('public', 'contract_rule_sets', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on contract_rule_sets');
SELECT table_privs_are('public', 'contract_rule_sets', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contract_rule_sets');

-- 15. contract_rule_versions
SELECT table_privs_are('public', 'contract_rule_versions', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on contract_rule_versions');
SELECT table_privs_are('public', 'contract_rule_versions', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contract_rule_versions');

-- 16. contractor_justifications
SELECT table_privs_are('public', 'contractor_justifications', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on contractor_justifications');
SELECT table_privs_are('public', 'contractor_justifications', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contractor_justifications');

-- 17. justification_evidence_uploads
SELECT table_privs_are('public', 'justification_evidence_uploads', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on justification_evidence_uploads');
SELECT table_privs_are('public', 'justification_evidence_uploads', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on justification_evidence_uploads');

-- 18. telegram_evidence_links
SELECT table_privs_are('public', 'telegram_evidence_links', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on telegram_evidence_links');
SELECT table_privs_are('public', 'telegram_evidence_links', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on telegram_evidence_links');

-- 19. telegram_evidence_metadata
SELECT table_privs_are('public', 'telegram_evidence_metadata', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on telegram_evidence_metadata');
SELECT table_privs_are('public', 'telegram_evidence_metadata', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on telegram_evidence_metadata');

-- 20. telegram_user_consents
SELECT table_privs_are('public', 'telegram_user_consents', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on telegram_user_consents');
SELECT table_privs_are('public', 'telegram_user_consents', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on telegram_user_consents');

-- 21. telegram_evidence_uploads
SELECT table_privs_are('public', 'telegram_evidence_uploads', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on telegram_evidence_uploads');
SELECT table_privs_are('public', 'telegram_evidence_uploads', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on telegram_evidence_uploads');

-- 22. telegram_chat_bindings
SELECT table_privs_are('public', 'telegram_chat_bindings', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on telegram_chat_bindings');
SELECT table_privs_are('public', 'telegram_chat_bindings', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on telegram_chat_bindings');

SELECT * FROM finish();
ROLLBACK;
