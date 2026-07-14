-- =============================================================================
-- pgTAP: 20260923000002_ledger_event_type_enum
-- CIA: I — ENUM assignment cast + invalid reject (22P02)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'ledger_event_type'
  ),
  'ledger_event_type enum exists'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_ledger_type'
      AND conrelid = 'public.sla_audit_ledger_v2'::regclass
  ),
  'chk_ledger_type CHECK removed'
);

SELECT is(
  (
    SELECT format_type(a.atttypid, a.atttypmod)
    FROM pg_attribute a
    WHERE a.attrelid = 'public.sla_audit_ledger_v2'::regclass
      AND a.attname = 'type'
      AND NOT a.attisdropped
  ),
  'ledger_event_type',
  'sla_audit_ledger_v2.type is ledger_event_type'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'ledger_event_type'
      AND e.enumlabel = 'SYSTEM_AUTO_CLOSE'
  ),
  'SYSTEM_AUTO_CLOSE present for autonomous closer'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'sla_audit_ledger_v2'
      AND t.tgname = 'trg_financial_guard' AND NOT t.tgisinternal
  ),
  'trg_financial_guard recreated after ENUM cast'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'sla_audit_ledger_v2'
      AND t.tgname = 'trg_financial_guard_credit' AND NOT t.tgisinternal
  ),
  'trg_financial_guard_credit recreated after ENUM cast'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_class
    WHERE relname = 'uq_ledger_sla_breach_once' AND relkind IN ('i', 'I')
  ),
  'uq_ledger_sla_breach_once recreated'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_class
    WHERE relname = 'uq_ledger_resolution_cycle_p0' AND relkind IN ('i', 'I')
  ),
  'uq_ledger_resolution_cycle_p0 recreated'
);

-- ── CIA:I — ASSIGNMENT cast text → ledger_event_type ─────────────────────────
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_cast
    WHERE castsource = 'text'::regtype
      AND casttarget = 'ledger_event_type'::regtype
  ),
  'pg_cast text → ledger_event_type ASSIGNMENT exists'
);

INSERT INTO public.organizations (id, name, status)
VALUES ('eeee0000-0000-4000-8000-0000000000e2', 'Org Enum Assign', 'ACTIVE')
ON CONFLICT DO NOTHING;

SELECT lives_ok(
  $$
  DO $body$
  DECLARE
    t text := 'SYSTEM_AUTO_CLOSE';
  BEGIN
    INSERT INTO public.sla_audit_ledger_v2
      (organization_id, type, operator_id, set_id, plan_version, payload, occurred_at_utc)
    VALUES (
      'eeee0000-0000-4000-8000-0000000000e2',
      t,
      'TEST',
      'enum-assign-text',
      0,
      '{}'::jsonb,
      now()
    );
  END
  $body$;
  $$,
  'INSERT via TEXT variable coerces to ledger_event_type (ASSIGNMENT cast)'
);

SELECT throws_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, operator_id, set_id, plan_version, payload, occurred_at_utc)
     VALUES (
       'eeee0000-0000-4000-8000-0000000000e2',
       'NOT_A_REAL_LEDGER_TYPE',
       'TEST',
       'enum-reject',
       0,
       '{}'::jsonb,
       now()
     ) $$,
  '22P02',
  NULL,
  'invalid ledger type rejected with 22P02'
);

SELECT * FROM finish();
ROLLBACK;
