-- =============================================================================
-- Migration: WS-4 Blindado — Heurística Temporal
--
-- Tables: telegram_evidence_uploads (add columns), telegram_evidence_links
-- RPC:    find_execution_for_telegram
-- Alerts: TELEGRAM_ORPHAN type added to operational_alerts
--
-- INV-6:  UTC everywhere (timestamptz), message.date as chronological anchor
-- INV-7:  Append-only enforcement on all tables
-- INV-9:  SHA-256 forensic hash preserved
-- INV-18: Zero-Trust — Telegram metadata never trusted
-- =============================================================================

-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs.
SET client_min_messages TO 'WARNING';

-- ── 1. Add WS-4 columns to telegram_evidence_uploads ─────────────────────────

ALTER TABLE public.telegram_evidence_uploads
  ADD COLUMN IF NOT EXISTS telegram_message_date TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE public.telegram_evidence_uploads
  ADD COLUMN IF NOT EXISTS requires_manual_link BOOLEAN NOT NULL DEFAULT false;

-- Index for orphan flagging (supervisor triage)
CREATE INDEX IF NOT EXISTS idx_teu_requires_manual_link
  ON public.telegram_evidence_uploads (organization_id, requires_manual_link, telegram_message_date DESC);

-- Index for timestamp discrepancy audit
CREATE INDEX IF NOT EXISTS idx_teu_message_vs_uploaded
  ON public.telegram_evidence_uploads (organization_id, telegram_message_date, uploaded_at_utc);

-- ── 2. Create telegram_evidence_links (append-only, immutable) ───────────────

CREATE TABLE IF NOT EXISTS public.telegram_evidence_links (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       UUID        NOT NULL,
  evidence_upload_id    UUID        NOT NULL REFERENCES public.telegram_evidence_uploads(id) ON DELETE CASCADE,
  execution_set_id      TEXT        NOT NULL,
  linked_at_utc         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  linked_by_user_id     UUID,
  source                TEXT        NOT NULL DEFAULT 'telegram'
    CONSTRAINT chk_tel_source CHECK (source IN ('telegram', 'manual', 'reconciliation'))
);

CREATE INDEX IF NOT EXISTS idx_tel_evidence_upload
  ON public.telegram_evidence_links (evidence_upload_id);

CREATE INDEX IF NOT EXISTS idx_tel_execution_set
  ON public.telegram_evidence_links (execution_set_id);

CREATE INDEX IF NOT EXISTS idx_tel_org_manual
  ON public.telegram_evidence_links (organization_id, source)
  WHERE source = 'manual';

-- Immutability: all fields frozen after insert (INV-7)
CREATE OR REPLACE FUNCTION public.prevent_tel_immutable_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_evidence_links: fully immutable (INV-7). UPDATE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tel_no_update ON public.telegram_evidence_links;
CREATE TRIGGER trg_tel_no_update
  BEFORE UPDATE ON public.telegram_evidence_links
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tel_immutable_mutation();

CREATE OR REPLACE FUNCTION public.prevent_tel_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_evidence_links: append-only (INV-7). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tel_no_delete ON public.telegram_evidence_links;
CREATE TRIGGER trg_tel_no_delete
  BEFORE DELETE ON public.telegram_evidence_links
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tel_delete();

ALTER TABLE public.telegram_evidence_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tel_select_own_org ON public.telegram_evidence_links;
CREATE POLICY tel_select_own_org
  ON public.telegram_evidence_links FOR SELECT
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')
  );

-- Service role (webhook) inserts links
DROP POLICY IF EXISTS tel_insert_service ON public.telegram_evidence_links;
CREATE POLICY tel_insert_service
  ON public.telegram_evidence_links FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS tel_select_super_admin ON public.telegram_evidence_links;
CREATE POLICY tel_select_super_admin
  ON public.telegram_evidence_links FOR SELECT
  USING ((auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE);

-- ── 3. Extend operational_alerts for TELEGRAM_ORPHAN ─────────────────────────

ALTER TABLE public.operational_alerts
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'telegram'
    CONSTRAINT chk_oa_source CHECK (source IN ('telegram', 'engine', 'manual'));

-- Extend valid_alert_type to include TELEGRAM_ORPHAN
ALTER TABLE public.operational_alerts
  DROP CONSTRAINT IF EXISTS valid_alert_type;

ALTER TABLE public.operational_alerts
  ADD CONSTRAINT valid_alert_type CHECK (alert_type IN ('NO_SHOW', 'EVIDENCE_GAP', 'PENALTY_APPLIED', 'TELEGRAM_ORPHAN'));

-- Index for supervisor triage of orphan alerts
CREATE INDEX IF NOT EXISTS idx_alerts_telegram_orphan
  ON public.operational_alerts (organization_id, status, severity, triggered_at_utc DESC)
  WHERE alert_type = 'TELEGRAM_ORPHAN' AND source = 'telegram';

-- ── 4. RPC: find_execution_for_telegram ─────────────────────────────────────

-- Encapsulates Latest-Wins strategy with retroactive window
-- Input: p_org_id, p_driver_id, p_message_ts (Unix timestamp)
-- Output: set_id or NULL
-- Window: [p_message_ts - 10min, p_message_ts + 4h]
-- Strategy: ORDER BY window_start_utc DESC LIMIT 1

CREATE OR REPLACE FUNCTION public.find_execution_for_telegram(
  p_org_id     UUID,
  p_driver_id  UUID,
  p_message_ts BIGINT
)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  -- Heurística Temporal:
  -- Busca execuções onde a foto foi tirada dentro da janela de 4h da execução,
  -- ou na janela de tolerância de 10min antes do início oficial.
  SELECT es.set_id
  FROM public.execution_states es
  INNER JOIN public.contractual_service_executions cse
    ON es.set_id = cse.set_id
  INNER JOIN public.plan_declarations pd
    ON cse.plan_declaration_id = pd.id
  INNER JOIN public.drivers d
    ON d.id = p_driver_id
  WHERE pd.organization_id = p_org_id
    AND es.status IN ('pending', 'executed', 'evidenceGap')
    -- Filtro de Veículo: Garante que o motorista só vincule às suas próprias execuções
    AND (es.planned_vehicle_id IS NULL OR es.planned_vehicle_id = d.license_number OR es.planned_vehicle_id = d.id::text)
    -- Janela: [T - 4h, T + 10min] -> T = window_start_utc
    -- msg_ts >= T - 10min  => T <= msg_ts + 10min
    -- msg_ts <= T + 4h     => T >= msg_ts - 4h
    AND es.window_start_utc >= to_timestamp(p_message_ts - 4 * 3600) AT TIME ZONE 'UTC'
    AND es.window_start_utc <= to_timestamp(p_message_ts + 600) AT TIME ZONE 'UTC'
  ORDER BY es.window_start_utc DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.find_execution_for_telegram(UUID, UUID, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_execution_for_telegram(UUID, UUID, BIGINT) TO authenticated;

-- ── 5. Update telegram_evidence_uploads RLS policy ───────────────────────────

-- Service role (webhook) inserts evidence records with new columns
DROP POLICY IF EXISTS teu_insert_service ON public.telegram_evidence_uploads;
CREATE POLICY teu_insert_service
  ON public.telegram_evidence_uploads FOR INSERT
  WITH CHECK (true);
