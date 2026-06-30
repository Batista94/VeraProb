BEGIN;
SELECT plan(6);

-- Setup
SET LOCAL search_path = public;

-- Verify table and columns exist
SELECT has_table('webhook_endpoints');
SELECT has_column('webhook_endpoints', 'url');

-- Test URL Constraint
SELECT lives_ok(
    $$
    INSERT INTO organizations (id, name, type, "domain", status) VALUES ('22222222-2222-2222-2222-222222222222', 'Org B', 'B2B', 'b.com', 'active');
    INSERT INTO webhook_endpoints (organization_id, url) VALUES ('22222222-2222-2222-2222-222222222222', 'https://example.com');
    $$,
    'Can insert valid https url'
);

SELECT throws_ok(
    $$
    INSERT INTO webhook_endpoints (organization_id, url) VALUES ('22222222-2222-2222-2222-222222222222', 'http://example.com');
    $$,
    '23514',
    NULL,
    'Cannot insert http url'
);

-- Check RLS
SELECT has_rls('webhook_endpoints');

-- Finish
SELECT * FROM finish();
ROLLBACK;
