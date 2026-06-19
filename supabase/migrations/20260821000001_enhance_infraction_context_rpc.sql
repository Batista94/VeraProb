-- =============================================================================
-- Migration: enhance_infraction_context_rpc — Issue 2
-- Purpose:   Adds clause_ref, primary_evidence_lat, and primary_evidence_lng
--            to the read_infraction_context JSONB output so the Dispute Portal
--            can format metrics with units and display reverse-geocoded addresses.
--
-- Pattern:   CREATE OR REPLACE FUNCTION (Zero-downtime, INV-DB).
--            No locking changes, no signature changes.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-26, INV-22.
-- Depends on: 20260819000003_read_infraction_context_rpc.sql
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.read_infraction_context(
  p_token UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_token_row  public.dispute_portal_tokens;
  v_queue      public.sanction_review_queue;
  v_org        public.organizations;
  v_now        TIMESTAMPTZ := NOW();
  v_measured   INT;
  v_threshold  INT;
  v_exceeded   INT;
  v_lat        TEXT;
  v_lng        TEXT;
  v_location   TEXT;
BEGIN
  -- Advisory lock normalises timing between FOUND and NOT FOUND paths (anti side-
  -- channel). Identical pattern to read_dispute_portal (QA-Sec T7).
  PERFORM pg_advisory_xact_lock(hashtextextended(p_token::text, 0));

  -- Load token row without FOR UPDATE — we intentionally do NOT increment
  -- access_count (read_dispute_portal already does it; double-increment = burn).
  SELECT * INTO v_token_row
    FROM public.dispute_portal_tokens
   WHERE token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_now > v_token_row.expires_at_utc THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.revoked_at_utc IS NOT NULL THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.access_count >= v_token_row.max_access_count THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Load queue entry (org-scoped via token binding — INV-1, INV-22).
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id              = v_token_row.queue_entry_id
     AND organization_id = v_token_row.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Load org (for branded carrier projection).
  SELECT * INTO v_org
    FROM public.organizations
   WHERE id = v_token_row.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Derive numeric fields from verdict_evidence JSONB.
  v_measured  := ROUND(COALESCE((v_queue.verdict_evidence ->> 'delta_value')::numeric,     0))::int;
  v_threshold := ROUND(COALESCE((v_queue.verdict_evidence ->> 'threshold_value')::numeric, 0))::int;
  v_exceeded  := CASE
    WHEN (v_queue.verdict_evidence ->> 'delta_value')    IS NOT NULL
     AND (v_queue.verdict_evidence ->> 'threshold_value') IS NOT NULL
    THEN v_measured - v_threshold
    ELSE NULL
  END;

  -- Location label: lat,lng when both present, else '-'.
  v_lat := v_queue.verdict_evidence ->> 'primary_evidence_lat';
  v_lng := v_queue.verdict_evidence ->> 'primary_evidence_lng';
  v_location := CASE
    WHEN v_lat IS NOT NULL AND v_lng IS NOT NULL THEN v_lat || ',' || v_lng
    ELSE '-'
  END;

  RETURN jsonb_build_object(
    'asset_identifier',   v_queue.vehicle_plate,
    'penalty_value_cents', (v_queue.verdict_evidence ->> 'fine_cents')::int,
    'measured_value',     v_measured,
    'threshold_value',    v_threshold,
    'exceeded_by',        v_exceeded,
    'occurred_at_utc',    (v_queue.verdict_evidence ->> 'primary_evidence_timestamp_utc')::timestamptz,
    'location_label',     v_location,
    'record_id',          v_queue.id::text,
    'org_display_name',   v_org.name,
    'org_cnpj',           v_org.cnpj,
    'org_logo_url',       COALESCE(v_org.logo_url, ''),
    'primary_evidence_lat', v_lat::numeric,
    'primary_evidence_lng', v_lng::numeric,
    'clause_ref',         v_queue.verdict_evidence ->> 'clause_ref'
  );

EXCEPTION
  -- Anti-oracle (INV-26): ALL failure paths → single opaque 42501.
  -- Unforeseen internal errors must not leak stack traces or table names to the
  -- carrier. Re-raise anything that isn't already 42501 as 42501.
  WHEN insufficient_privilege THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
END;
$$;

-- anon + authenticated only. service_role intentionally omitted: REVOKE FROM PUBLIC
-- strips it (lesson: reference_revoke_from_public_strips_service_role) and we do
-- not re-grant — this is an external carrier-facing function, not a backend tool.
REVOKE ALL ON FUNCTION public.read_infraction_context(UUID) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.read_infraction_context(UUID)
  TO anon, authenticated;

RESET client_min_messages;
