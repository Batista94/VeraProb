-- Migration: Explicit Data API Grants for Category A (Standard Client Tables)
-- Rule: INV-DATA-API-GRANT (Tables in public schema must explicitly grant API role access)
-- Target: authenticated (SELECT, INSERT, UPDATE, DELETE), service_role (ALL)

-- 1. contracts
REVOKE ALL ON TABLE public.contracts FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contracts TO authenticated;
GRANT ALL ON TABLE public.contracts TO service_role;

-- 2. contractors
REVOKE ALL ON TABLE public.contractors FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contractors TO authenticated;
GRANT ALL ON TABLE public.contractors TO service_role;

-- 3. vehicles
REVOKE ALL ON TABLE public.vehicles FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.vehicles TO authenticated;
GRANT ALL ON TABLE public.vehicles TO service_role;

-- 4. routes
REVOKE ALL ON TABLE public.routes FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.routes TO authenticated;
GRANT ALL ON TABLE public.routes TO service_role;

-- 5. operational_zones
REVOKE ALL ON TABLE public.operational_zones FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.operational_zones TO authenticated;
GRANT ALL ON TABLE public.operational_zones TO service_role;

-- 6. plan_declarations
REVOKE ALL ON TABLE public.plan_declarations FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.plan_declarations TO authenticated;
GRANT ALL ON TABLE public.plan_declarations TO service_role;

-- 7. contractual_service_executions
REVOKE ALL ON TABLE public.contractual_service_executions FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contractual_service_executions TO authenticated;
GRANT ALL ON TABLE public.contractual_service_executions TO service_role;

-- 8. execution_states
REVOKE ALL ON TABLE public.execution_states FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.execution_states TO authenticated;
GRANT ALL ON TABLE public.execution_states TO service_role;

-- 9. sanction_review_queue
REVOKE ALL ON TABLE public.sanction_review_queue FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.sanction_review_queue TO authenticated;
GRANT ALL ON TABLE public.sanction_review_queue TO service_role;

-- 10. operational_alerts
REVOKE ALL ON TABLE public.operational_alerts FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.operational_alerts TO authenticated;
GRANT ALL ON TABLE public.operational_alerts TO service_role;

-- 11. contractual_financial_snapshot
REVOKE ALL ON TABLE public.contractual_financial_snapshot FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contractual_financial_snapshot TO authenticated;
GRANT ALL ON TABLE public.contractual_financial_snapshot TO service_role;

-- 12. sla_audit_ledger_v2
REVOKE ALL ON TABLE public.sla_audit_ledger_v2 FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.sla_audit_ledger_v2 TO authenticated;
GRANT ALL ON TABLE public.sla_audit_ledger_v2 TO service_role;

-- 13. service_manifests
REVOKE ALL ON TABLE public.service_manifests FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.service_manifests TO authenticated;
GRANT ALL ON TABLE public.service_manifests TO service_role;

-- 14. contract_rule_sets
REVOKE ALL ON TABLE public.contract_rule_sets FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contract_rule_sets TO authenticated;
GRANT ALL ON TABLE public.contract_rule_sets TO service_role;

-- 15. contract_rule_versions
REVOKE ALL ON TABLE public.contract_rule_versions FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contract_rule_versions TO authenticated;
GRANT ALL ON TABLE public.contract_rule_versions TO service_role;

-- 16. contractor_justifications
REVOKE ALL ON TABLE public.contractor_justifications FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contractor_justifications TO authenticated;
GRANT ALL ON TABLE public.contractor_justifications TO service_role;

-- 17. justification_evidence_uploads
REVOKE ALL ON TABLE public.justification_evidence_uploads FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.justification_evidence_uploads TO authenticated;
GRANT ALL ON TABLE public.justification_evidence_uploads TO service_role;

-- 18. telegram_evidence_links
REVOKE ALL ON TABLE public.telegram_evidence_links FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.telegram_evidence_links TO authenticated;
GRANT ALL ON TABLE public.telegram_evidence_links TO service_role;

-- 19. telegram_evidence_metadata
REVOKE ALL ON TABLE public.telegram_evidence_metadata FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.telegram_evidence_metadata TO authenticated;
GRANT ALL ON TABLE public.telegram_evidence_metadata TO service_role;

-- 20. telegram_user_consents
REVOKE ALL ON TABLE public.telegram_user_consents FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.telegram_user_consents TO authenticated;
GRANT ALL ON TABLE public.telegram_user_consents TO service_role;

-- 21. telegram_evidence_uploads
REVOKE ALL ON TABLE public.telegram_evidence_uploads FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.telegram_evidence_uploads TO authenticated;
GRANT ALL ON TABLE public.telegram_evidence_uploads TO service_role;

-- 22. telegram_chat_bindings
REVOKE ALL ON TABLE public.telegram_chat_bindings FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.telegram_chat_bindings TO authenticated;
GRANT ALL ON TABLE public.telegram_chat_bindings TO service_role;
