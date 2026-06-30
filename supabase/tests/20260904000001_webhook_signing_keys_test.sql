BEGIN;
SELECT plan(6);

-- Setup

-- Verify table and columns exist
SELECT has_table('webhook_signing_keys');
SELECT has_column('webhook_signing_keys', 'organization_id');
SELECT has_column('webhook_signing_keys', 'status');

-- Test Exclude Constraint
SELECT lives_ok(
    $$
    INSERT INTO organizations (id, name) VALUES ('11111111-1111-1111-1111-111111111111', 'Org A');
    INSERT INTO webhook_signing_keys (organization_id, version, status) VALUES ('11111111-1111-1111-1111-111111111111', 1, 'active');
    $$,
    'Can insert first active key'
);

SELECT throws_ok(
    $$
    INSERT INTO webhook_signing_keys (organization_id, version, status) VALUES ('11111111-1111-1111-1111-111111111111', 2, 'active');
    $$,
    '23P01',
    NULL,
    'Cannot insert second active key'
);

SELECT lives_ok(
    $$
    INSERT INTO webhook_signing_keys (organization_id, version, status) VALUES ('11111111-1111-1111-1111-111111111111', 2, 'retiring');
    $$,
    'Can insert retiring key'
);



-- Finish
SELECT * FROM finish();
ROLLBACK;
