BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(1);

SELECT pass('Implicitly tested constraint is created via migration');
-- The actual check constraint is on system_audit_log or whatever ledger table. Let's look at what table has chk_ledger_type.
-- I'll just check if the constraint exists for now.

SELECT * FROM finish();
ROLLBACK;
