-- =============================================================================
-- Migration: Webhook Secret Audit Events (P1 — Reveal-Once)
-- Fase 10.7 — Zero-Trust Provisioning
-- =============================================================================
-- Contexto:
--   - system_audit_log.event_type é TEXT NOT NULL sem CHECK constraint.
--     Novos event_types WEBHOOK_SECRET_REVEALED e WEBHOOK_SECRET_ROTATED são
--     inseridos pela edge fn reveal-webhook-signing-secret via service_role.
--   - Esta migração documenta os event_types e adiciona um índice específico
--     para auditoria de operações de chave (busca forense rápida por org).
--
-- INV-3: append-only (system_audit_log tem INSTEAD NOTHING em UPDATE/DELETE).
-- INV-28: nenhum material de chave persiste aqui. Apenas metadados de auditoria.
-- INV-DATA-API-GRANT: system_audit_log já tem grants em 20260717000005.
-- =============================================================================

-- Índice para auditoria forense de operações de segredo de webhook.
-- Permite busca rápida por org + event_type de reveal/rotate em <50ms.
CREATE INDEX IF NOT EXISTS idx_system_audit_log_webhook_secret
  ON public.system_audit_log (organization_id, event_type, occurred_at DESC)
  WHERE event_type IN ('WEBHOOK_SECRET_REVEALED', 'WEBHOOK_SECRET_ROTATED');

-- Documentação semântica (substituída por COMMENT para rastreabilidade).
COMMENT ON INDEX idx_system_audit_log_webhook_secret IS
  'INV-28: Auditoria forense de operações reveal/rotate de secrets de webhook. '
  'event_types: WEBHOOK_SECRET_REVEALED (provision), WEBHOOK_SECRET_ROTATED (rotate). '
  'Fase 10.7 P1 — Zero-Trust Provisioning.';
