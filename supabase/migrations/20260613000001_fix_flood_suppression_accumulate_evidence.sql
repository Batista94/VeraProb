-- Migration: Fix trg_suppress_flood_alerts — Accumulate evidence_ids instead of silent drop
--
-- Problem: The previous trigger returned NULL on flood detection, causing all
--          evidence photos after the first to be silently discarded from the
--          operational_alerts context. The StreamProvider read stale context
--          with only 1 evidence_id, making the Evidence Strip show "1 FOTO".
--
-- Solution: Convert the trigger from a silent suppressor to an "upsert-style"
--           accumulator. When a duplicate TELEGRAM_ORPHAN arrives within 15min,
--           instead of RETURN NULL, the trigger:
--             1. Extracts the new evidence_id from NEW.context->'evidence_id'
--             2. Appends it to the existing alert's context->'evidence_ids' array
--             3. RETURN NULL (still suppresses the duplicate INSERT)
--
--          This ensures the ACTIVE alert always holds the full evidence_ids array,
--          and the StreamProvider / Realtime feed reflects the current burst count.
--
-- Invariants:
--   INV-7: The alert row itself is updated (not deleted). The evidence records
--          in telegram_evidence_uploads remain immutable and unaffected.
--   INV-1: UPDATE is org-scoped (WHERE organization_id = NEW.organization_id).
--   INV-9: UTC timestamps are not altered; only context JSONB is modified.
--   INV-16: Trigger uses the existing idx_alerts_flood_suppression partial index.
--
-- Note on INV-7 scope: operational_alerts is an "operational projection" table,
--   not an immutable ledger. Its context JSONB accumulates evidence references
--   as new facts arrive — this is analogous to array_append on viewed_by_user_ids
--   (already permitted by the command_center migration). The evidence itself
--   (telegram_evidence_uploads) remains fully immutable.

-- ── Drop old function and recreate as accumulator ─────────────────────────────

CREATE OR REPLACE FUNCTION public.suppress_flood_alerts()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing_alert_id UUID;
  v_new_evidence_id   TEXT;
BEGIN
  -- Find the existing ACTIVE alert for same (org, entity, alert_type) within 15min window.
  SELECT id INTO v_existing_alert_id
  FROM public.operational_alerts
  WHERE organization_id = NEW.organization_id
    AND entity_id       = NEW.entity_id
    AND alert_type      = NEW.alert_type
    AND status          = 'ACTIVE'
    AND triggered_at_utc > NOW() - INTERVAL '15 minutes'
  LIMIT 1;

  IF v_existing_alert_id IS NULL THEN
    -- No active flood window: let the INSERT proceed normally.
    RETURN NEW;
  END IF;

  -- Extract evidence_id from the incoming alert context (if present).
  v_new_evidence_id := NEW.context ->> 'evidence_id';

  IF v_new_evidence_id IS NOT NULL THEN
    -- Accumulate: append the new evidence_id into the existing alert's context array.
    -- jsonb_set creates 'evidence_ids' if absent, initialising from [] + the first id
    -- already present as 'evidence_id' when the array doesn't exist yet.
    UPDATE public.operational_alerts
    SET context = jsonb_set(
      -- Ensure evidence_ids array exists (seed from evidence_id on first accumulation)
      CASE
        WHEN context ? 'evidence_ids' THEN context
        ELSE jsonb_set(
          context,
          '{evidence_ids}',
          -- Seed with the original single evidence_id (already stored on insert)
          COALESCE(
            jsonb_build_array(context ->> 'evidence_id'),
            '[]'::jsonb
          )
        )
      END,
      '{evidence_ids}',
      -- Append the new one — use || to avoid duplicates via jsonb array dedup trick
      (
        COALESCE(
          CASE WHEN context ? 'evidence_ids' THEN context -> 'evidence_ids'
               ELSE jsonb_build_array(context ->> 'evidence_id')
          END,
          '[]'::jsonb
        ) || to_jsonb(v_new_evidence_id)
      )
    )
    WHERE id = v_existing_alert_id
      -- Guard: only if the evidence_id isn't already in the array (idempotency).
      AND NOT (
        COALESCE(context -> 'evidence_ids', '[]'::jsonb) @> to_jsonb(v_new_evidence_id)
      );
  END IF;

  -- Suppress the new row: evidence is already sealed in telegram_evidence_uploads.
  RETURN NULL;
END;
$$;

-- The trigger definition (name, table, timing) does not change — only the function body.
-- trg_suppress_flood_alerts remains BEFORE INSERT, FOR EACH ROW,
-- WHEN (NEW.alert_type = 'TELEGRAM_ORPHAN').
-- No DROP/CREATE TRIGGER needed — CREATE OR REPLACE FUNCTION is enough.

-- ── Verify the function replaced correctly (informational comment) ─────────────
-- SELECT prosrc FROM pg_proc WHERE proname = 'suppress_flood_alerts';
