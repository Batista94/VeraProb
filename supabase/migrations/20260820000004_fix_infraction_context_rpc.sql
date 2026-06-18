-- =============================================================================
-- Migration: fix_infraction_context_rpc — Desserialization Fix
-- Purpose:   Fixes the mapping of 'measured_value' and 'threshold_value' in
--            read_infraction_context to extract them correctly from the
--            verdict_evidence JSONB, rather than reading 'delta_value' and
--            rounding it to an int, which causes incorrect displays.
--            Also prioritizes the human-readable 'address' over Lat/Lng string.
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
  -- Advisory lock normalises timing between FOUND and NOT FOUND paths
  PERFORM pg_advisory_xact_lock(hashtextextended(p_token::text, 0));

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

  -- Load queue entry
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id              = v_token_row.queue_entry_id
     AND organization_id = v_token_row.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Load org
  SELECT * INTO v_org
    FROM public.organizations
   WHERE id = v_token_row.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Derive numeric fields from verdict_evidence JSONB.
  v_measured  := ROUND(COALESCE((v_queue.verdict_evidence ->> 'measured_value')::numeric, 0))::int;
  v_threshold := ROUND(COALESCE((v_queue.verdict_evidence ->> 'threshold_value')::numeric, 0))::int;
  
  -- Exceeded calculation (delta)
  v_exceeded  := CASE
    WHEN (v_queue.verdict_evidence ->> 'measured_value')  IS NOT NULL
     AND (v_queue.verdict_evidence ->> 'threshold_value') IS NOT NULL
    THEN v_measured - v_threshold
    ELSE NULL
  END;

  -- Location label: geofence_name > address > location_label > lat,lng > '-'
  v_lat := v_queue.verdict_evidence ->> 'primary_evidence_lat';
  v_lng := v_queue.verdict_evidence ->> 'primary_evidence_lng';
  v_location := COALESCE(
    NULLIF(v_queue.verdict_evidence ->> 'geofence_name', ''),
    NULLIF(v_queue.verdict_evidence ->> 'address', ''),
    NULLIF(v_queue.verdict_evidence ->> 'location_label', ''),
    CASE
      WHEN v_lat IS NOT NULL AND v_lng IS NOT NULL THEN v_lat || ',' || v_lng
      ELSE '-'
    END
  );

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
    'org_logo_url',       COALESCE(v_org.logo_url, '')
  );

EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
END;
$$;

REVOKE ALL ON FUNCTION public.read_infraction_context(UUID) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.read_infraction_context(UUID)
  TO anon, authenticated;

RESET client_min_messages;
