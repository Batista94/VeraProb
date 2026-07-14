-- =============================================================================
-- pgTAP: 20260924000001_system_auto_start_ledger_v2
-- CIA: I — SYSTEM_AUTO_START writes v2 only (INV-3 SSOT)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(4);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'ledger_event_type'
      AND e.enumlabel = 'SYSTEM_AUTO_START'
  ),
  'SYSTEM_AUTO_START present on ledger_event_type'
);

SELECT ok(
  position('sla_audit_ledger_v2' in pg_get_functiondef(
    'public.process_gps_for_execution_transitions(uuid, text, double precision, double precision, timestamptz)'::regprocedure
  )) > 0,
  'process_gps function body references sla_audit_ledger_v2'
);

SELECT ok(
  position('INSERT INTO public.sla_audit_ledger (' in pg_get_functiondef(
    'public.process_gps_for_execution_transitions(uuid, text, double precision, double precision, timestamptz)'::regprocedure
  )) = 0,
  'process_gps no longer inserts into legacy sla_audit_ledger'
);

SELECT ok(
  position('v_contract_id::uuid' in pg_get_functiondef(
    'public.process_gps_for_execution_transitions(uuid, text, double precision, double precision, timestamptz)'::regprocedure
  )) > 0,
  'process_gps casts TEXT contract_id to UUID for v2 insert'
);

SELECT * FROM finish();
ROLLBACK;
