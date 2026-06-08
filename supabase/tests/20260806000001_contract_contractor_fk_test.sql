BEGIN;
SELECT plan(5);

-- 1. Column exists
SELECT has_column(
  'public', 'contracts', 'contractor_id',
  'contracts has column contractor_id'
);

-- 2. Column is nullable (rollout — INV-DB)
SELECT ok(
  (SELECT is_nullable = 'YES'
     FROM information_schema.columns
    WHERE table_schema='public' AND table_name='contracts'
      AND column_name='contractor_id'),
  'contractor_id is nullable'
);

-- 3. FK targets public.contractors(id)
SELECT ok(
  EXISTS (
    SELECT 1
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = 'public' AND tc.table_name = 'contracts'
      AND kcu.column_name = 'contractor_id'
      AND ccu.table_name = 'contractors' AND ccu.column_name = 'id'
  ),
  'contractor_id is a FK to public.contractors(id)'
);

-- Setup: fresh org + contract with a free-text contractor_name.
INSERT INTO public.organizations (id, name, cnpj, created_at)
VALUES ('c1000000-0000-0000-0000-00000000000c', 'FK Test Corp', '11.222.333/0001-44', NOW());

INSERT INTO public.contracts (
  id, organization_id, name, contractor_name,
  valid_from_utc, valid_until_utc, status, created_at_utc, penalty_multiplier
) VALUES (
  'c2000000-0000-0000-0000-00000000000c',
  'c1000000-0000-0000-0000-00000000000c',
  'Contrato FK Test', 'Cliente X',
  NOW() - INTERVAL '1 day', NOW() + INTERVAL '30 days', 'active', NOW(), 1.0
);

-- Run the migration's backfill statements (B + C).
INSERT INTO public.contractors (organization_id, name, tax_id, primary_email, contact_name)
SELECT DISTINCT c.organization_id, btrim(c.contractor_name),
       'PENDING-' || substr(md5(c.organization_id::text || '|' || btrim(c.contractor_name)), 1, 14),
       'pending+' || md5(c.organization_id::text || '|' || btrim(c.contractor_name)) || '@placeholder.invalid',
       btrim(c.contractor_name)
FROM public.contracts c
WHERE c.organization_id = 'c1000000-0000-0000-0000-00000000000c'
  AND c.contractor_name IS NOT NULL AND btrim(c.contractor_name) <> ''
ON CONFLICT (organization_id, name) DO NOTHING;

UPDATE public.contracts c
SET contractor_id = ct.id
FROM public.contractors ct
WHERE ct.organization_id = c.organization_id
  AND ct.name = btrim(c.contractor_name)
  AND c.contractor_id IS NULL
  AND c.organization_id = 'c1000000-0000-0000-0000-00000000000c';

-- 4. Contractor registry now holds the promoted client.
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.contractors
    WHERE organization_id = 'c1000000-0000-0000-0000-00000000000c' AND name = 'Cliente X'
  ),
  'backfill promoted contractor_name into contractors'
);

-- 5. Contract points at the matching contractor.
SELECT is(
  (SELECT ct.name
     FROM public.contracts c
     JOIN public.contractors ct ON ct.id = c.contractor_id
    WHERE c.id = 'c2000000-0000-0000-0000-00000000000c'),
  'Cliente X',
  'contract.contractor_id resolves to the correct contractor'
);

SELECT * FROM finish();
ROLLBACK;
