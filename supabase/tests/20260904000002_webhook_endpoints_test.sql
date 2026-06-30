BEGIN;
SELECT plan(4);

-- Setup

-- Verify table and columns exist
SELECT has_table('webhook_endpoints');
SELECT has_column('webhook_endpoints', 'url');

-- Test URL Constraint
SELECT lives_ok(
    $$
    INSERT INTO organizations (id, name) VALUES ('22222222-2222-2222-2222-222222222222', 'Org B');
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



-- Finish
SELECT * FROM finish();
ROLLBACK;
