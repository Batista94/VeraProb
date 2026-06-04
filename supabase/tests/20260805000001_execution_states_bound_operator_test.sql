BEGIN;
SELECT plan(3);

-- 1. Column exists
SELECT has_column(
  'public',
  'execution_states',
  'bound_operator_id',
  'execution_states has column bound_operator_id'
);

-- 2. Column is nullable (additive, zero-downtime — INV-DB)
SELECT ok(
  (SELECT is_nullable = 'YES'
     FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'execution_states'
      AND column_name = 'bound_operator_id'),
  'bound_operator_id is nullable'
);

-- 3. Foreign key targets public.drivers(id)
SELECT ok(
  EXISTS (
    SELECT 1
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
     AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON tc.constraint_name = ccu.constraint_name
     AND tc.table_schema = ccu.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = 'public'
      AND tc.table_name = 'execution_states'
      AND kcu.column_name = 'bound_operator_id'
      AND ccu.table_name = 'drivers'
      AND ccu.column_name = 'id'
  ),
  'bound_operator_id is a FK to public.drivers(id)'
);

SELECT * FROM finish();
ROLLBACK;
