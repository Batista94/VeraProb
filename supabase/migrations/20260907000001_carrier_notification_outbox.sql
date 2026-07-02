-- =============================================================================
-- Migration: P3 — Carrier Notification Outbox + Unified Transactional Trigger
-- =============================================================================
-- Invariants: INV-1 (org filter), INV-2 (RLS JWT path), INV-3 (append-only),
--             INV-4 (fine_cents BIGINT), INV-6 (TIMESTAMPTZ), INV-DB (zero-downtime),
--             INV-DATA-API-GRANT (explicit grants), INV-22 (tenant isolation)
-- =============================================================================

-- ── 1. carrier_notification_outbox ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.carrier_notification_outbox (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID        NOT NULL REFERENCES public.organizations(id),
  ledger_entry_id     UUID        NOT NULL,
  carrier_email       TEXT        NOT NULL
    CONSTRAINT chk_cno_carrier_email_nonempty CHECK (char_length(carrier_email) > 0),
  event_type          TEXT        NOT NULL,
  verdict_outcome     TEXT        NOT NULL,
  fine_cents          BIGINT      NOT NULL DEFAULT 0
    CONSTRAINT chk_cno_fine_cents_non_neg CHECK (fine_cents >= 0),
  portal_token        UUID,
  status              TEXT        NOT NULL DEFAULT 'PENDING'
    CONSTRAINT chk_cno_status CHECK (status IN ('PENDING','SENT','FAILED','DEAD')),
  attempt_count       INT         NOT NULL DEFAULT 0
    CONSTRAINT chk_cno_attempt_count_non_neg CHECK (attempt_count >= 0),
  next_attempt_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resend_message_id   TEXT,
  last_error          TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at             TIMESTAMPTZ,
  -- Idempotência: um único registro por (org, ledger_entry, carrier_email)
  CONSTRAINT uq_cno_org_ledger_carrier UNIQUE (organization_id, ledger_entry_id, carrier_email),
  CONSTRAINT fk_cno_ledger FOREIGN KEY (organization_id, ledger_entry_id) REFERENCES public.sla_audit_ledger_v2(organization_id, id)
);

COMMENT ON TABLE public.carrier_notification_outbox IS
  'P3: Carrier notification outbox — append-only (INV-3). One row per (org, ledger_entry, carrier_email). Drained by dispatch-carrier-notifications Edge Function via Resend.';

-- ── Indexes ───────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_cno_drain
  ON public.carrier_notification_outbox (status, next_attempt_at)
  WHERE status IN ('PENDING', 'FAILED');

CREATE INDEX IF NOT EXISTS idx_cno_org_status
  ON public.carrier_notification_outbox (organization_id, status);

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE public.carrier_notification_outbox ENABLE ROW LEVEL SECURITY;

-- Only service_role (SECURITY DEFINER functions) may manipulate rows directly.
-- Authenticated users have no direct access; reads go through RPCs only.
CREATE POLICY "cno_service_role_all" ON public.carrier_notification_outbox
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Tenant read-only (for future observability screen, org-scoped — INV-2).
-- Claim path: app_metadata.org_id (unified 20260317000001). Top-level
-- 'organization_id' claim does NOT exist → would match NULL → zero rows.
CREATE POLICY "cno_tenant_select" ON public.carrier_notification_outbox
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── Explicit Grants (INV-DATA-API-GRANT) ─────────────────────────────────────

REVOKE ALL ON TABLE public.carrier_notification_outbox FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.carrier_notification_outbox TO authenticated;
GRANT ALL    ON TABLE public.carrier_notification_outbox TO service_role;

-- ── Imutabilidade (INV-3) ─────────────────────────────────────────────────────
-- Campos selados: id, organization_id, ledger_entry_id, carrier_email,
-- event_type, verdict_outcome, fine_cents, portal_token, created_at.
-- Mutáveis: status, attempt_count, next_attempt_at, resend_message_id,
--           last_error, sent_at.

CREATE OR REPLACE FUNCTION public.cno_immutability_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.id               <> OLD.id               OR
     NEW.organization_id  <> OLD.organization_id  OR
     NEW.ledger_entry_id  <> OLD.ledger_entry_id  OR
     NEW.carrier_email    <> OLD.carrier_email     OR
     NEW.event_type       <> OLD.event_type        OR
     NEW.verdict_outcome  <> OLD.verdict_outcome   OR
     NEW.fine_cents       <> OLD.fine_cents        OR
     NEW.created_at       <> OLD.created_at
  THEN
    RAISE EXCEPTION 'carrier_notification_outbox: immutable field mutation (INV-3). id: %', OLD.id;
  END IF;
  -- Coalesce: portal_token e fine_cents são imutáveis após serem definidos não-null
  IF OLD.portal_token IS NOT NULL AND NEW.portal_token IS DISTINCT FROM OLD.portal_token THEN
    RAISE EXCEPTION 'carrier_notification_outbox: portal_token já selado (INV-3). id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cno_immutability ON public.carrier_notification_outbox;
CREATE TRIGGER trg_cno_immutability
  BEFORE UPDATE ON public.carrier_notification_outbox
  FOR EACH ROW EXECUTE FUNCTION public.cno_immutability_guard();

CREATE OR REPLACE FUNCTION public.cno_no_delete_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'carrier_notification_outbox is append-only (INV-3). DELETE blocked. id: %', OLD.id;
END;
$$;

DROP TRIGGER IF EXISTS trg_cno_no_delete ON public.carrier_notification_outbox;
CREATE TRIGGER trg_cno_no_delete
  BEFORE DELETE ON public.carrier_notification_outbox
  FOR EACH ROW EXECUTE FUNCTION public.cno_no_delete_guard();

-- =============================================================================
-- 2. Refactor: enqueue_verdict_webhooks → enqueue_resolution_events
--    CREATE OR REPLACE — mesma assinatura, mesmo trigger físico.
--    Passa a enfileirar em webhook_delivery_logs (ERP) E
--    carrier_notification_outbox (Resend) dentro do MESMO bloco PL/pgSQL.
--    Atomicidade garantida pela transação do trigger AFTER INSERT.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enqueue_resolution_events()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_endpoint      RECORD;
  v_payload       JSONB;
  v_reason_code   TEXT;
  v_queue_entry   UUID;
  v_fine_cents    BIGINT;
  v_outcome       TEXT;
  v_carrier_email TEXT;
  v_portal_token  UUID;
BEGIN
  -- Only fire for terminal verdict states
  IF NEW.type NOT IN (
    'VERDICT_SEALED', 'VERDICT_REFUSED',
    'DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED',
    'DISPUTE_RETRACTED', 'SANCTION_ACKNOWLEDGED'
  ) THEN
    RETURN NEW;
  END IF;

  -- reason_code: validated against catalogue
  v_reason_code := NEW.payload->>'reason_code';
  IF v_reason_code IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.dispute_reason_codes WHERE code = v_reason_code
    ) THEN
      v_reason_code := NULL;
    END IF;
  END IF;

  -- Derive shared values from ledger entry
  v_queue_entry := (NEW.payload->>'queue_entry_id')::uuid;
  v_fine_cents  := COALESCE((NEW.payload->'verdict_evidence'->>'fine_cents')::bigint, 0);
  v_outcome     := CASE NEW.type
    WHEN 'VERDICT_SEALED'         THEN 'SEALED'
    WHEN 'VERDICT_REFUSED'        THEN 'REFUSED'
    WHEN 'DISPUTE_ACCEPTED'       THEN 'ACCEPTED'
    WHEN 'DISPUTE_OVERTURNED'     THEN 'OVERTURNED'
    WHEN 'DISPUTE_RETRACTED'      THEN 'RETRACTED'
    WHEN 'SANCTION_ACKNOWLEDGED'  THEN 'ACKNOWLEDGED'
  END;

  -- Build ERP webhook payload (same fields as before — no regression)
  v_payload := jsonb_build_object(
    'schema_version', '1.0',
    'event_type', NEW.type,
    'occurred_at', NEW.occurred_at_utc,
    'organization_id', NEW.organization_id,
    'case', jsonb_build_object(
      'ledger_entry_id', NEW.id,
      'queue_entry_id', NEW.payload->>'queue_entry_id'
    ),
    'evidence', jsonb_build_object(
      'attachment_hashes', COALESCE((
        SELECT jsonb_agg(d.sha256_hash ORDER BY d.sha256_hash)
        FROM public.dispute_evidence_attachments d
        WHERE d.organization_id = NEW.organization_id
          AND d.queue_entry_id  = v_queue_entry
          AND d.deleted_at IS NULL
      ), '[]'::jsonb)
    ),
    'verdict', jsonb_build_object(
      'outcome', v_outcome,
      'reason_code', v_reason_code,
      'resolution_reason', NEW.payload->>'resolution_reason'
    ),
    'financial', jsonb_build_object(
      'fine_cents', v_fine_cents,
      'currency', 'BRL'
    )
  );

  -- ── OUTBOX 1: webhook_delivery_logs (ERP) ──────────────────────────────────
  -- Fan-out: one row per active endpoint of the org
  FOR v_endpoint IN
    SELECT id
    FROM public.webhook_endpoints
    WHERE organization_id = NEW.organization_id
      AND is_active = true
      AND deleted_at IS NULL
  LOOP
    INSERT INTO public.webhook_delivery_logs (
      organization_id,
      endpoint_id,
      ledger_entry_id,
      event_type,
      payload,
      status,
      signing_key_id
    ) VALUES (
      NEW.organization_id,
      v_endpoint.id,
      NEW.id,
      NEW.type,
      v_payload,
      'PENDING',
      NULL
    );
  END LOOP;

  -- ── OUTBOX 2: carrier_notification_outbox (Resend) ─────────────────────────
  -- Recipient = the AUTUADA carrier, resolved from the verdict's own contract:
  --   ledger.contract_id → contracts.id → contracts.contractor_id → contractors.primary_email
  -- Org-scoped (INV-1). ledger.contract_id carries no enforced FK (append-only
  -- ingest), so the join is defensive (no match → no email → skip).
  -- Deliberately NOT organizations.contact_email: that is the embarcador's own
  -- mailbox — notifying it would leave the carrier's "não fui avisado" defense
  -- standing, defeating the entire purpose of this outbox.
  IF NEW.contract_id IS NOT NULL THEN
    SELECT ct.primary_email
    INTO v_carrier_email
    FROM public.contracts c
    JOIN public.contractors ct ON ct.id = c.contractor_id
    WHERE c.id = NEW.contract_id
      AND c.organization_id = NEW.organization_id;
  END IF;

  -- Resolve portal_token do Portal de Disputas (leitura — token read-only já
  -- gerado pelo RPC generate_dispute_portal_token no momento do seal)
  IF v_queue_entry IS NOT NULL THEN
    SELECT token INTO v_portal_token
    FROM public.dispute_portal_tokens
    WHERE organization_id = NEW.organization_id
      AND queue_entry_id  = v_queue_entry
      AND revoked_at_utc IS NULL
      AND expires_at_utc > NOW()
    ORDER BY created_at_utc DESC
    LIMIT 1;
  END IF;

  -- Enqueue only for a DELIVERABLE address (Zero-Trust). Skip NULL/empty and the
  -- '@placeholder.invalid' backfill sentinel (20260806000001): a guaranteed bounce
  -- would only pollute the outbox with DEAD noise. The sealed verdict itself stays
  -- the immutable system of record in the ledger regardless.
  IF v_carrier_email IS NOT NULL
     AND char_length(trim(v_carrier_email)) > 0
     AND lower(trim(v_carrier_email)) NOT LIKE '%@placeholder.invalid' THEN
    INSERT INTO public.carrier_notification_outbox (
      organization_id,
      ledger_entry_id,
      carrier_email,
      event_type,
      verdict_outcome,
      fine_cents,
      portal_token,
      status,
      next_attempt_at
    ) VALUES (
      NEW.organization_id,
      NEW.id,
      trim(v_carrier_email),
      NEW.type,
      v_outcome,
      v_fine_cents,
      v_portal_token,
      'PENDING',
      NOW()
    )
    ON CONFLICT (organization_id, ledger_entry_id, carrier_email) DO NOTHING;
    -- ON CONFLICT DO NOTHING: idempotência — replay do trigger não duplica
  END IF;

  RETURN NEW;
END;
$$;

-- ── Repoint existing trigger to the renamed function ─────────────────────────
-- The trigger physical name is preserved (trg_enqueue_verdict_webhooks) to
-- avoid breaking any monitoring that references the trigger name.
-- The function it executes is now enqueue_resolution_events.
DROP TRIGGER IF EXISTS trg_enqueue_verdict_webhooks ON public.sla_audit_ledger_v2;
CREATE TRIGGER trg_enqueue_verdict_webhooks
  AFTER INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW EXECUTE FUNCTION public.enqueue_resolution_events();

-- =============================================================================
-- 3. RPC: drain_pending_carrier_notifications (SKIP LOCKED)
--    Espelha drain_pending_webhooks — reserva rows com lock para drain concorrente.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.drain_pending_carrier_notifications(
  p_org_id UUID  DEFAULT NULL,
  p_limit  INT   DEFAULT 20
)
RETURNS TABLE (
  id              UUID,
  org_id_out      UUID,
  ledger_entry_id UUID,
  carrier_email   TEXT,
  event_type      TEXT,
  verdict_outcome TEXT,
  fine_cents      BIGINT,
  portal_token    UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.carrier_notification_outbox AS cno
  SET
    -- Lease: push next_attempt_at 2min out so overlapping/slow drains can't
    -- re-pick the same row before the dispatcher marks it SENT/FAILED.
    -- Mirrors drain_pending_webhooks (DELIVERING lease). Prevents duplicate
    -- Resend calls; carrier_notification_fail overwrites next_attempt_at on failure.
    status          = 'PENDING',
    attempt_count   = cno.attempt_count + 1,
    next_attempt_at = NOW() + INTERVAL '2 minutes'
  WHERE cno.id IN (
    SELECT c.id
    FROM public.carrier_notification_outbox c
    WHERE c.status         IN ('PENDING', 'FAILED')
      AND c.next_attempt_at <= NOW()
      AND (p_org_id IS NULL OR c.organization_id = p_org_id)
    ORDER BY c.next_attempt_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  RETURNING
    cno.id,
    cno.organization_id  AS org_id_out,
    cno.ledger_entry_id,
    cno.carrier_email,
    cno.event_type,
    cno.verdict_outcome,
    cno.fine_cents,
    cno.portal_token;
END;
$$;

REVOKE ALL ON FUNCTION public.drain_pending_carrier_notifications(UUID, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.drain_pending_carrier_notifications(UUID, INT) TO service_role;

-- =============================================================================
-- 4. RPC: carrier_notification_fail (backoff + DEAD after max attempts)
--    Espelha webhook_delivery_fail.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.carrier_notification_fail(
  p_notification_id UUID,
  p_org_id          UUID,
  p_error           TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_attempts   INT;
  v_max        INT  := 5;
  v_backoff_s  INT;
  v_new_status TEXT;
BEGIN
  -- Fetch current attempt_count (already incremented by drain)
  SELECT attempt_count
  INTO v_attempts
  FROM public.carrier_notification_outbox
  WHERE id = p_notification_id
    AND organization_id = p_org_id; -- INV-1: org-scope guard

  IF NOT FOUND THEN
    RETURN; -- Anti-oracle: silent no-op for wrong org
  END IF;

  IF v_attempts >= v_max THEN
    v_new_status := 'DEAD';
    v_backoff_s  := 0;
  ELSE
    v_new_status := 'FAILED';
    -- Exponential backoff: 30s, 60s, 120s, 240s (max 4 retries before DEAD)
    v_backoff_s  := LEAST(30 * (2 ^ (v_attempts - 1)), 3600);
  END IF;

  UPDATE public.carrier_notification_outbox
  SET
    status          = v_new_status,
    last_error      = left(p_error, 255),
    next_attempt_at = CASE
      WHEN v_new_status = 'FAILED' THEN NOW() + (v_backoff_s || ' seconds')::interval
      ELSE next_attempt_at
    END
  WHERE id = p_notification_id
    AND organization_id = p_org_id;
END;
$$;

REVOKE ALL ON FUNCTION public.carrier_notification_fail(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carrier_notification_fail(UUID, UUID, TEXT) TO service_role;
