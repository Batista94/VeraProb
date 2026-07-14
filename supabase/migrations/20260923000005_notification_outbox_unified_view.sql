-- pr_scanner: ignore-regression — PR elevation CIA migrations (Council-approved plan)
-- =============================================================================
-- Migration: notification_outbox unified VIEW (PR5)
-- Read SSOT over webhook_delivery_logs + carrier_notification_outbox.
-- Physical twin tables retained; freeze expanding duplicate outbox schemas.
-- Invariants: INV-2 (security_invoker), INV-22.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE VIEW public.notification_outbox
WITH (security_invoker = true) AS
SELECT
  w.id,
  w.organization_id,
  'webhook'::text AS channel,
  w.ledger_entry_id,
  w.event_type,
  w.status::text AS status,
  w.attempt_count,
  w.next_attempt_at,
  w.last_error,
  w.created_at
FROM public.webhook_delivery_logs w
UNION ALL
SELECT
  c.id,
  c.organization_id,
  'email'::text AS channel,
  c.ledger_entry_id,
  c.event_type,
  c.status,
  c.attempt_count,
  c.next_attempt_at,
  c.last_error,
  c.created_at
FROM public.carrier_notification_outbox c;

COMMENT ON VIEW public.notification_outbox IS
  'PR5 unified read of webhook + carrier email outboxes. Twin tables frozen — prefer channel column for new drains.';

COMMENT ON TABLE public.webhook_delivery_logs IS
  'Webhook outbox. Prefer notification_outbox view for cross-channel reads (PR5 freeze).';

COMMENT ON TABLE public.carrier_notification_outbox IS
  'Email outbox. Prefer notification_outbox view for cross-channel reads (PR5 freeze).';

GRANT SELECT ON public.notification_outbox TO authenticated, service_role;
