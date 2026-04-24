-- Alert Command Center: reconciliation_shortcut source + Realtime + viewed_by_user_ids
--
-- Task 2 of AlertsTriadeDrawer → Proactive Command Center evolution.
--
-- Changes:
--   1. Extend telegram_evidence_links.source CHECK to include 'reconciliation_shortcut'
--   2. Add viewed_by_user_ids column to operational_alerts for collision awareness
--   3. Enable Supabase Realtime on operational_alerts for push-based drawer updates
--
-- Invariants: INV-1 (org-scoped), INV-3 (append-only links), INV-16 (lightweight)

-- ── 1. Extend source CHECK on telegram_evidence_links ────────────────────────

ALTER TABLE public.telegram_evidence_links
  DROP CONSTRAINT IF EXISTS chk_tel_source;

ALTER TABLE public.telegram_evidence_links
  ADD CONSTRAINT chk_tel_source
  CHECK (source IN ('telegram', 'manual', 'reconciliation', 'reconciliation_shortcut'));

-- ── 2. Add viewed_by_user_ids for collision awareness ────────────────────────

ALTER TABLE public.operational_alerts
  ADD COLUMN IF NOT EXISTS viewed_by_user_ids UUID[] NOT NULL DEFAULT '{}';

-- Index for collision awareness queries (GIN for array containment)
CREATE INDEX IF NOT EXISTS idx_alerts_viewed_by
  ON public.operational_alerts USING GIN (viewed_by_user_ids)
  WHERE status = 'ACTIVE';

-- ── 3. Enable Supabase Realtime on operational_alerts ────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE public.operational_alerts;

-- ── 4. RPC: mark_alert_viewed (idempotent collision awareness) ───────────────

CREATE OR REPLACE FUNCTION public.mark_alert_viewed(
  p_alert_id UUID,
  p_user_id  UUID
)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.operational_alerts
  SET viewed_by_user_ids = array_append(viewed_by_user_ids, p_user_id)
  WHERE id = p_alert_id
    AND NOT (p_user_id = ANY(viewed_by_user_ids));
$$;

REVOKE ALL ON FUNCTION public.mark_alert_viewed(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_alert_viewed(UUID, UUID) TO authenticated;
