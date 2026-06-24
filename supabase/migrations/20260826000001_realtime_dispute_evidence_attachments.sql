-- =============================================================================
-- Migration: realtime_dispute_evidence_attachments — PKG3 (Dispute Reality)
-- Purpose:   Publish public.dispute_evidence_attachments on the supabase_realtime
--            publication so the authenticated auditor queue refreshes the moment
--            carrier counter-evidence is finalized. register_portal_evidence
--            (20260818000005) inserts a row here 1:1 when it promotes a portal
--            submission to PENDING_AUDIT — that INSERT is the realtime tick the
--            Flutter `_PortalSubmissionsZone` listens to (a single shared
--            channel, INV-16; never one channel per card).
--
--            portal_evidence_submissions itself is deny-all RLS (quarantine
--            paths must not leak) and therefore CANNOT be streamed by the
--            authenticated client; dispute_evidence_attachments is its
--            authenticated-readable, tenant-scoped projection (20260813000001).
--
-- Realtime authorization: postgres_changes for `authenticated` is gated by the
-- table's own RLS (dea_select_own_org: organization_id = app_metadata.org_id AND
-- role IN (TENANT_ADMIN, AUDITOR)). Tenant-A never receives Tenant-B change
-- events (INV-22). Mirrors the proven sanction_review_queue publication
-- (20260406000001) — no DDL on the table, publication membership only.
--
-- Council: Senior ✅ · QA-Security ✅ (RLS-gated realtime, no new read surface).
-- Invariants: INV-2, INV-16 (single shared channel), INV-22.
-- Append-only: idempotent publication ADD; no schema change → types unaffected.
-- Depends on: 20260813000001 (dispute_evidence_attachments + dea_select_own_org).
-- =============================================================================

SET client_min_messages TO 'WARNING';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_publication_tables
     WHERE pubname    = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename  = 'dispute_evidence_attachments'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.dispute_evidence_attachments;
  END IF;
END;
$$;

RESET client_min_messages;
