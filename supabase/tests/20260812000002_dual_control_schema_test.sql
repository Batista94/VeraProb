BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- 1–3. Threshold / TTL columns (org baseline + contract override).
SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'organizations'
       AND column_name = 'dual_control_threshold_cents' AND data_type = 'bigint'
  ),
  'organizations.dual_control_threshold_cents exists (BIGINT)'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'organizations'
       AND column_name = 'dual_control_ttl_hours'
       AND column_default LIKE '48%'
  ),
  'organizations.dual_control_ttl_hours exists with default 48'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'contracts'
       AND column_name = 'dual_control_threshold_cents' AND data_type = 'bigint'
  ),
  'contracts.dual_control_threshold_cents exists (override)'
);

-- 4–7. Peer-review control columns on the queue.
SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'sanction_review_queue'
       AND column_name = 'first_reviewer_id'
  ),
  'sanction_review_queue.first_reviewer_id exists'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'sanction_review_queue'
       AND column_name = 'peer_review_proposed_action'
  ),
  'sanction_review_queue.peer_review_proposed_action exists'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'sanction_review_queue'
       AND column_name = 'peer_review_origin_status'
  ),
  'sanction_review_queue.peer_review_origin_status exists'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'sanction_review_queue'
       AND column_name = 'peer_review_expires_at'
       AND data_type = 'timestamp with time zone'
  ),
  'sanction_review_queue.peer_review_expires_at exists (TIMESTAMPTZ)'
);

-- 8. Widened status CHECK admits pending_peer_review.
SELECT ok(
  pg_get_constraintdef(
    (SELECT oid FROM pg_constraint
      WHERE conname = 'chk_srq_status'
        AND conrelid = 'public.sanction_review_queue'::regclass)
  ) LIKE '%pending_peer_review%',
  'chk_srq_status admits pending_peer_review'
);

-- 9. Proposed-action domain constraint exists.
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'chk_srq_peer_action'
       AND conrelid = 'public.sanction_review_queue'::regclass
  ),
  'chk_srq_peer_action constrains the proposed action domain'
);

-- 10-12. ledger_event_type enum admits the peer-review lifecycle facts.
SELECT ok(
  EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type ty ON ty.oid=e.enumtypid
          JOIN pg_namespace n ON n.oid=ty.typnamespace
          WHERE n.nspname='public' AND ty.typname='ledger_event_type'
            AND e.enumlabel='PEER_REVIEW_REQUESTED'),
  'ledger_event_type admits PEER_REVIEW_REQUESTED'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type ty ON ty.oid=e.enumtypid
          JOIN pg_namespace n ON n.oid=ty.typnamespace
          WHERE n.nspname='public' AND ty.typname='ledger_event_type'
            AND e.enumlabel='PEER_REVIEW_DECLINED'),
  'ledger_event_type admits PEER_REVIEW_DECLINED'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type ty ON ty.oid=e.enumtypid
          JOIN pg_namespace n ON n.oid=ty.typnamespace
          WHERE n.nspname='public' AND ty.typname='ledger_event_type'
            AND e.enumlabel='PEER_REVIEW_EXPIRED'),
  'ledger_event_type admits PEER_REVIEW_EXPIRED'
);

SELECT * FROM finish();
ROLLBACK;
