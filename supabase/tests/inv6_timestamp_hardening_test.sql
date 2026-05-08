-- =============================================================================
-- pgTAP: INV-6 Schema Validation (CI Gate)
--
-- Prevents accidental introduction of bare TIMESTAMP or device-clock DEFAULTs.
-- Run via: supabase test
-- =============================================================================

BEGIN;
SELECT plan(5);

-- ── Test 1: No bare 'timestamp without time zone' in public schema ────────────
SELECT is(
  (SELECT COUNT(*)::int FROM information_schema.columns
   WHERE table_schema = 'public'
     AND data_type = 'timestamp without time zone'),
  0,
  'INV-6: No bare timestamp columns in public schema'
);

-- ── Test 2: telegram_message_date has no DEFAULT ──────────────────────────────
SELECT is(
  (SELECT column_default FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'telegram_evidence_uploads'
     AND column_name = 'telegram_message_date'),
  NULL,
  'INV-6: telegram_message_date has no DEFAULT (device-clock column)'
);

-- ── Test 3: INSERT without telegram_message_date fails ────────────────────────
SELECT throws_ok(
  $$INSERT INTO telegram_evidence_uploads (
    id, organization_id, driver_id, chat_id, telegram_message_id,
    file_name, forensic_hash, storage_path
  ) VALUES (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    1, 1, 'test.jpg',
    repeat('a', 64), '/test'
  )$$,
  '23502', -- NOT NULL violation error code
  NULL,
  'INV-6: INSERT without telegram_message_date raises NOT NULL violation'
);

-- ── Test 4: organizations.tool_cost_cents exists and is BIGINT ────────────────
SELECT col_type_is(
  'public', 'organizations', 'tool_cost_cents', 'bigint',
  'INV-4: tool_cost_cents is BIGINT on organizations'
);

-- ── Test 5: shadow_executions.message_ts has no DEFAULT ───────────────────────
SELECT is(
  (SELECT column_default FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'shadow_executions'
     AND column_name = 'message_ts'),
  NULL,
  'INV-6: shadow_executions.message_ts has no DEFAULT (device-clock column)'
);

SELECT * FROM finish();
ROLLBACK;
