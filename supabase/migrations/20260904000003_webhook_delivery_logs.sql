-- =============================================================================
-- Migration: Webhook Delivery Logs
-- INV-22: Tenant Isolation
-- =============================================================================

CREATE TYPE webhook_delivery_status AS ENUM ('PENDING', 'DELIVERING', 'SUCCESS', 'FAILED', 'DEAD');

CREATE TABLE IF NOT EXISTS public.webhook_delivery_logs (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  endpoint_id      UUID        NOT NULL REFERENCES public.webhook_endpoints(id) ON DELETE CASCADE,
  ledger_entry_id  UUID        NOT NULL,
  signing_key_id   UUID        REFERENCES public.webhook_signing_keys(id) ON DELETE SET NULL,
  event_type       TEXT        NOT NULL,
  payload          JSONB       NOT NULL,
  status           webhook_delivery_status NOT NULL DEFAULT 'PENDING',
  attempt_count    INT         NOT NULL DEFAULT 0,
  next_attempt_at  TIMESTAMPTZ,
  last_error       TEXT,
  signature        TEXT,
  dispatched_at    TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_webhook_delivery_logs_idempotency
    UNIQUE (organization_id, ledger_entry_id, endpoint_id, event_type),
  CONSTRAINT fk_webhook_delivery_logs_ledger
    FOREIGN KEY (organization_id, ledger_entry_id) REFERENCES public.sla_audit_ledger_v2 (organization_id, id) ON DELETE CASCADE
);

-- RLS
ALTER TABLE public.webhook_delivery_logs ENABLE ROW LEVEL SECURITY;

-- Drain hot-path index: the dispatcher scans (org, created_at) for non-terminal rows only.
-- Partial keeps it tiny — SUCCESS/DEAD rows (the vast majority over time) are excluded.
CREATE INDEX idx_webhook_delivery_logs_drain
  ON public.webhook_delivery_logs (organization_id, created_at)
  WHERE status IN ('PENDING', 'FAILED', 'DELIVERING');

-- Grants (Data API constraint). Rows are written ONLY by the SECURITY DEFINER enqueue trigger
-- (owner privileges), never by a tenant session — so authenticated gets SELECT only, no INSERT.
GRANT SELECT ON public.webhook_delivery_logs TO authenticated;
-- Dispatcher (service_role) drains (SELECT) and advances status/retry (UPDATE)
GRANT SELECT, UPDATE ON public.webhook_delivery_logs TO service_role;

CREATE POLICY "Authenticated users can read their org webhook delivery logs"
  ON public.webhook_delivery_logs
  AS PERMISSIVE
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "Tenant Admins can view webhook delivery logs"
  ON public.webhook_delivery_logs
  AS PERMISSIVE
  FOR ALL
  TO authenticated
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  )
  WITH CHECK (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  );

-- ── Immutability Trigger ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.webhook_delivery_logs_immutability_guard()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'webhook_delivery_logs is append-only: DELETE is forbidden'
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- Allowed column changes: status, attempt_count, next_attempt_at, last_error, dispatched_at, signature
    IF NEW.payload IS DISTINCT FROM OLD.payload
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.endpoint_id IS DISTINCT FROM OLD.endpoint_id
       OR NEW.ledger_entry_id IS DISTINCT FROM OLD.ledger_entry_id
       OR NEW.event_type IS DISTINCT FROM OLD.event_type
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'webhook_delivery_logs is append-only: payload and forensic relations cannot be updated'
        USING ERRCODE = 'restrict_violation';
    END IF;

    -- signing_key_id is one-shot
    IF NEW.signing_key_id IS DISTINCT FROM OLD.signing_key_id THEN
      IF OLD.signing_key_id IS NOT NULL THEN
        RAISE EXCEPTION 'webhook_delivery_logs: signing_key_id can only be set once'
          USING ERRCODE = 'restrict_violation';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_webhook_delivery_logs_immutability
  BEFORE UPDATE OR DELETE ON public.webhook_delivery_logs
  FOR EACH ROW EXECUTE FUNCTION public.webhook_delivery_logs_immutability_guard();

COMMENT ON TABLE public.webhook_delivery_logs IS 'Transactional outbox for webhook dispatch. Payload is immutable.';
