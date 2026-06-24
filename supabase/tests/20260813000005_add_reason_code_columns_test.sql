BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(9);

-- ── Structure: the three structured reason-code columns exist ────────────────
SELECT has_column('public', 'sanction_review_queue', 'rejection_reason_code',
  'rejection_reason_code column added');
SELECT has_column('public', 'sanction_review_queue', 'resolution_reason_code',
  'resolution_reason_code column added');
SELECT has_column('public', 'sanction_review_queue', 'peer_review_reason_code',
  'peer_review_reason_code column added');

-- ── FK integrity: each column references the closed catalogue (23503) ────────
-- An unknown code must be rejected by the FK to dispute_reason_codes(code).
SELECT throws_ok(
  $$ INSERT INTO public.sanction_review_queue
       (organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
        status, rejection_reason_code)
     VALUES (gen_random_uuid(), gen_random_uuid(), 'FK_R', 'C_FK_R', '{}'::jsonb,
             'rejected', 'NOT_A_REAL_CODE') $$,
  '23503', NULL,
  'rejection_reason_code FK rejects an unknown code');

SELECT throws_ok(
  $$ INSERT INTO public.sanction_review_queue
       (organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
        status, resolution_reason_code)
     VALUES (gen_random_uuid(), gen_random_uuid(), 'FK_S', 'C_FK_S', '{}'::jsonb,
             'applied', 'NOT_A_REAL_CODE') $$,
  '23503', NULL,
  'resolution_reason_code FK rejects an unknown code');

SELECT throws_ok(
  $$ INSERT INTO public.sanction_review_queue
       (organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
        status, peer_review_reason_code)
     VALUES (gen_random_uuid(), gen_random_uuid(), 'FK_P', 'C_FK_P', '{}'::jsonb,
             'pending', 'NOT_A_REAL_CODE') $$,
  '23503', NULL,
  'peer_review_reason_code FK rejects an unknown code');

-- ── A valid catalogue code is accepted ───────────────────────────────────────
SELECT lives_ok(
  $$ INSERT INTO public.sanction_review_queue
       (organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
        status, rejection_reason_code)
     VALUES (gen_random_uuid(), gen_random_uuid(), 'OK_R', 'C_OK_R', '{}'::jsonb,
             'rejected', 'LEGACY_UNCLASSIFIED') $$,
  'a valid catalogue code is accepted by the FK');

-- ── The immutability trigger does NOT guard reason-code columns ──────────────
-- Proves the resolution RPCs (and the backfill below) can set these post-insert.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000d2c50', gen_random_uuid(), gen_random_uuid(),
   'MUT', 'C_MUT', '{}'::jsonb, 'disputed');

SELECT lives_ok(
  $$ UPDATE public.sanction_review_queue
        SET resolution_reason_code = 'LEGACY_UNCLASSIFIED'
      WHERE id = '00000000-0000-0000-0000-0000000d2c50' $$,
  'setting a reason code post-insert is not blocked by the immutability trigger');

-- ── H3 backfill semantics: legacy free-text rows get LEGACY_UNCLASSIFIED ─────
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, rejection_reason)
VALUES
  ('00000000-0000-0000-0000-0000000d2c51', gen_random_uuid(), gen_random_uuid(),
   'BACKFILL', 'C_BACKFILL', '{}'::jsonb, 'rejected', 'old free-text reason');

UPDATE public.sanction_review_queue
   SET rejection_reason_code = 'LEGACY_UNCLASSIFIED'
 WHERE rejection_reason IS NOT NULL AND rejection_reason_code IS NULL;

SELECT is(
  (SELECT rejection_reason_code FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000d2c51'),
  'LEGACY_UNCLASSIFIED',
  'backfill maps legacy free-text rejection_reason to LEGACY_UNCLASSIFIED');

SELECT * FROM finish();
ROLLBACK;
