-- pr_scanner: ignore-regression — publication-membership only, INV-22 RLS-gated; QA-Security Council APPROVE 2026-07-02
-- =============================================================================
-- Migration: realtime_webhook_delivery_logs — Fase 10.7 (P4 gap fix)
-- Purpose:   Publish public.webhook_delivery_logs on the supabase_realtime
--            publication. O painel WebhookManagementScreen consome
--            deliveryLogStreamProvider (supabase .stream()); sem a publicação
--            o stream entrega apenas o fetch inicial e NUNCA recebe updates —
--            a "observabilidade realtime" degrada silenciosamente (invisível
--            a analyze/pgTAP funcionais).
--
-- Realtime authorization: postgres_changes para `authenticated` é gated pelo
-- RLS da própria tabela ("Authenticated users can read their org webhook
-- delivery logs": organization_id = app_metadata.org_id, 20260904000003).
-- Tenant-A nunca recebe eventos de Tenant-B (INV-22). Espelha o padrão
-- comprovado de dispute_evidence_attachments (20260826000001) — membership de
-- publicação apenas, sem DDL na tabela.
--
-- Invariants: INV-2, INV-16 (single shared channel), INV-22.
-- Append-only: idempotent publication ADD; sem mudança de schema → types
-- inalterados.
-- Depends on: 20260904000003 (webhook_delivery_logs + RLS org-scoped).
-- =============================================================================

SET client_min_messages TO 'WARNING';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_publication_tables
     WHERE pubname    = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename  = 'webhook_delivery_logs'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.webhook_delivery_logs;
  END IF;
END;
$$;

RESET client_min_messages;
