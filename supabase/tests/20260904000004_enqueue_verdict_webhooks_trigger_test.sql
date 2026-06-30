BEGIN;
SELECT plan(1);

-- Setup
SET LOCAL search_path = public;

-- Verify trigger exists
SELECT has_trigger('sla_audit_ledger_v2', 'trg_enqueue_verdict_webhooks');

-- Finish
SELECT * FROM finish();
ROLLBACK;
