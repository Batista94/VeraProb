-- =============================================================================
-- Migration: Telegram Self-Link — Vinculação Manual de Evidência Órfã
--
-- Tables: telegram_pending_links (lookup, ephemeral)
-- RPCs:   find_pending_trips_for_driver, resolve_telegram_orphan_with_link
-- Constraint: extend chk_tel_source for 'telegram_self_link'
--
-- INV-1:  org_id on all queries
-- INV-3:  telegram_evidence_links remains append-only
-- INV-7:  telegram_evidence_uploads NEVER updated — linking via separate table
-- INV-6:  UTC everywhere
-- INV-26: Expired and not-found return identical error (no oracle attacks)
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. telegram_pending_links (ephemeral lookup for inline keyboard) ─────────
--
-- Short-lived rows mapping a short_id (8 chars) to an evidence+execution pair.
-- Rows expire after 24h. Cleanup is opportunistic (inside resolve RPC) since
-- pg_cron requires Supabase Pro (INV-23: Free-Tier First).

CREATE TABLE IF NOT EXISTS public.telegram_pending_links (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  short_id            TEXT        NOT NULL,
  organization_id     UUID        NOT NULL,
  evidence_upload_id  UUID        NOT NULL REFERENCES public.telegram_evidence_uploads(id),
  execution_set_id    TEXT        NOT NULL,
  driver_id           UUID        NOT NULL,
  created_at_utc      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at_utc      TIMESTAMPTZ NOT NULL,

  CONSTRAINT uq_tpl_short_id UNIQUE (short_id),
  CONSTRAINT chk_tpl_short_id_len CHECK (char_length(short_id) = 8)
);

CREATE INDEX IF NOT EXISTS idx_tpl_expires
  ON public.telegram_pending_links (expires_at_utc);

CREATE INDEX IF NOT EXISTS idx_tpl_evidence
  ON public.telegram_pending_links (evidence_upload_id);

-- RLS: service role (webhook) does all operations; no authenticated access needed.
ALTER TABLE public.telegram_pending_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tpl_service_all ON public.telegram_pending_links;
CREATE POLICY tpl_service_all
  ON public.telegram_pending_links FOR ALL
  USING (true) WITH CHECK (true);

-- ── 2. Extend chk_tel_source to include 'telegram_self_link' ────────────────

ALTER TABLE public.telegram_evidence_links
  DROP CONSTRAINT IF EXISTS chk_tel_source;

ALTER TABLE public.telegram_evidence_links
  ADD CONSTRAINT chk_tel_source
  CHECK (source IN ('telegram', 'manual', 'reconciliation', 'reconciliation_shortcut', 'telegram_self_link'));

-- ── 3. RPC: find_pending_trips_for_driver ────────────────────────────────────
--
-- Busca secundária: viagens pendentes do motorista, ordenadas pela mais próxima
-- de NOW(). Reutiliza o padrão de matching vehicle/driver da
-- find_execution_for_telegram, com normalização de placa (UPPER + remove hífens).
--
-- Returns: TABLE(set_id, window_start_utc) — max p_limit rows.

CREATE OR REPLACE FUNCTION public.find_pending_trips_for_driver(
  p_org_id    UUID,
  p_driver_id UUID,
  p_limit     INT DEFAULT 3
)
RETURNS TABLE(set_id TEXT, window_start_utc TIMESTAMPTZ)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT es.set_id, es.window_start_utc
  FROM public.execution_states es
  INNER JOIN public.contractual_service_executions cse
    ON es.set_id = cse.set_id
  INNER JOIN public.plan_declarations pd
    ON cse.plan_declaration_id = pd.id
  INNER JOIN public.drivers d
    ON d.id = p_driver_id
  WHERE pd.organization_id = p_org_id
    AND es.status = 'pending'
    AND (
      es.planned_vehicle_id IS NULL
      OR UPPER(REPLACE(es.planned_vehicle_id, '-', ''))
         = UPPER(REPLACE(d.license_number, '-', ''))
      OR es.planned_vehicle_id = d.id::text
    )
  ORDER BY ABS(EXTRACT(EPOCH FROM (es.window_start_utc - NOW())))
  LIMIT p_limit;
$$;

REVOKE ALL ON FUNCTION public.find_pending_trips_for_driver(UUID, UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_pending_trips_for_driver(UUID, UUID, INT) TO authenticated;

-- ── 4. RPC: resolve_telegram_orphan_with_link ────────────────────────────────
--
-- Atomic transaction: validates pending link → inserts evidence link →
-- resolves orphan alert → cleans up ALL pending links for that evidence.
--
-- Returns: the execution set_id on success, NULL on validation failure.
-- Caller checks NULL to determine error type (expired vs identity mismatch).
--
-- Error codes via RAISE:
--   'PGRST' || 'expired'  → link expired or not found (INV-26: same message)
--   'PGRST' || 'identity' → driver mismatch

CREATE OR REPLACE FUNCTION public.resolve_telegram_orphan_with_link(
  p_short_id   TEXT,
  p_driver_id  UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pending       RECORD;
  v_resolved_set  TEXT;
BEGIN
  -- 1. Opportunistic cleanup of expired rows (lightweight, index-backed)
  DELETE FROM public.telegram_pending_links
  WHERE expires_at_utc < NOW();

  -- 2. Fetch pending link by short_id
  SELECT tpl.evidence_upload_id,
         tpl.execution_set_id,
         tpl.organization_id,
         tpl.driver_id,
         tpl.expires_at_utc
  INTO v_pending
  FROM public.telegram_pending_links tpl
  WHERE tpl.short_id = p_short_id;

  -- 3. Not found (already cleaned up or never existed) — INV-26: same as expired
  IF NOT FOUND THEN
    RAISE EXCEPTION 'expired'
      USING ERRCODE = 'P0001';
  END IF;

  -- 4. Expiry check (belt-and-suspenders; cleanup above may miss race conditions)
  IF v_pending.expires_at_utc < NOW() THEN
    -- Clean this specific row
    DELETE FROM public.telegram_pending_links WHERE short_id = p_short_id;
    RAISE EXCEPTION 'expired'
      USING ERRCODE = 'P0001';
  END IF;

  -- 5. Identity validation: driver who clicks must be the driver who uploaded
  IF v_pending.driver_id <> p_driver_id THEN
    RAISE EXCEPTION 'identity'
      USING ERRCODE = 'P0002';
  END IF;

  -- 6. INSERT evidence link (source = 'telegram_self_link')
  --    23505 (unique violation) is allowed to propagate — caller handles idempotency
  INSERT INTO public.telegram_evidence_links (
    organization_id,
    evidence_upload_id,
    execution_set_id,
    source
  ) VALUES (
    v_pending.organization_id,
    v_pending.evidence_upload_id,
    v_pending.execution_set_id,
    'telegram_self_link'
  );

  v_resolved_set := v_pending.execution_set_id;

  -- 7. Resolve TELEGRAM_ORPHAN alert atomically (ACTIVE → RESOLVED)
  --    Skip lifecycle intermediate state since this is a system-initiated resolution.
  --    The alert may not exist (race condition) — that's fine.
  UPDATE public.operational_alerts
  SET status = 'RESOLVED',
      acknowledged_at_utc = NOW(),
      acknowledged_by_user_id = NULL,
      resolved_at_utc = NOW()
  WHERE alert_type = 'TELEGRAM_ORPHAN'
    AND organization_id = v_pending.organization_id
    AND status = 'ACTIVE'
    AND context->>'evidence_id' = v_pending.evidence_upload_id::text;

  -- 8. Cleanup ALL pending links for this evidence (not just the clicked one)
  DELETE FROM public.telegram_pending_links
  WHERE evidence_upload_id = v_pending.evidence_upload_id;

  RETURN v_resolved_set;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_telegram_orphan_with_link(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_telegram_orphan_with_link(TEXT, UUID) TO authenticated;
