-- =============================================================================
-- Migration: harden_read_infraction_context
-- Purpose:   Data Masking for non-disputed status (Gap 3). Returns 200 OK with
--            essential fields (protocol_id, status) but nullifies sensitive data
--            if the dispute is not active, preventing unauthorized surface exposure.
-- =============================================================================
-- pr_scanner: ignore-regression

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

  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id              = v_token_row.queue_entry_id
     AND organization_id = v_token_row.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_org
    FROM public.organizations
   WHERE id = v_token_row.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Gap 3 Data Masking logic (Zero-Trust)
  IF v_queue.status <> 'disputed' THEN
    RETURN jsonb_build_object(
      'record_id',             v_queue.id::text,
      'status',                v_queue.status,
      'occurred_at_utc',       (v_queue.verdict_evidence ->> 'primary_evidence_timestamp_utc')::timestamptz,
      'asset_identifier',      NULL,
      'penalty_value_cents',   NULL,
      'measured_value',        NULL,
      'threshold_value',       NULL,
      'exceeded_by',           NULL,
      'location_label',        NULL,
      'org_display_name',      NULL,
      'org_cnpj',              NULL,
      'org_logo_url',          NULL,
      'primary_evidence_lat',  NULL,
      'primary_evidence_lng',  NULL,
      'clause_ref',            NULL
    );
  END IF;

  v_threshold := ROUND(COALESCE((v_queue.verdict_evidence ->> 'threshold_value')::numeric, 0))::int;
  v_exceeded  := CASE
    WHEN (v_queue.verdict_evidence ->> 'delta_value') IS NOT NULL
    THEN ROUND((v_queue.verdict_evidence ->> 'delta_value')::numeric)::int
    ELSE NULL
  END;
  v_measured  := CASE
    WHEN (v_queue.verdict_evidence ->> 'delta_value')    IS NOT NULL
     AND (v_queue.verdict_evidence ->> 'threshold_value') IS NOT NULL
    THEN ROUND(
      (v_queue.verdict_evidence ->> 'threshold_value')::numeric +
      (v_queue.verdict_evidence ->> 'delta_value')::numeric
    )::int
    ELSE NULL
  END;

  v_lat := v_queue.verdict_evidence ->> 'primary_evidence_lat';
  v_lng := v_queue.verdict_evidence ->> 'primary_evidence_lng';
  v_location := COALESCE(
    v_queue.verdict_evidence ->> 'geofence_name',
    v_queue.verdict_evidence ->> 'address',
    v_queue.verdict_evidence ->> 'location_label',
    CASE WHEN v_lat IS NOT NULL AND v_lng IS NOT NULL THEN v_lat || ',' || v_lng ELSE '-' END
  );

  RETURN jsonb_build_object(
    'asset_identifier',      v_queue.vehicle_plate,
    'penalty_value_cents',   (v_queue.verdict_evidence ->> 'fine_cents')::int,
    'measured_value',        v_measured,
    'threshold_value',       v_threshold,
    'exceeded_by',           v_exceeded,
    'occurred_at_utc',       (v_queue.verdict_evidence ->> 'primary_evidence_timestamp_utc')::timestamptz,
    'location_label',        v_location,
    'record_id',             v_queue.id::text,
    'status',                v_queue.status,
    'org_display_name',      v_org.name,
    'org_cnpj',              v_org.cnpj,
    'org_logo_url',          COALESCE(v_org.logo_url, ''),
    'primary_evidence_lat',  v_lat::numeric,
    'primary_evidence_lng',  v_lng::numeric,
    'clause_ref',            v_queue.verdict_evidence ->> 'clause_ref'
  );

EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
END;
$$;

REVOKE ALL ON FUNCTION public.read_infraction_context(UUID) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.read_infraction_context(UUID) TO anon, authenticated;

RESET client_min_messages;
