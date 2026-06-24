-- Migration: read_infraction_context RPC — carrier-facing infraction projection
--
-- Why: the dispute portal page calls Future.wait([readDispute, readInfractionContext]).
-- read_infraction_context never existed in any migration → PGRST202 → the bare
-- catch(_) in the gateway rewrote the error to "Link inválido ou expirado", and
-- each failed load consumed one access_count slot (token burn). This migration
-- creates the missing RPC.
--
-- Security model (QA-Security ratification: explicit carrier disclosure):
--   - SECURITY DEFINER: anon has no JWT → bypasses RLS (mirrors read_dispute_portal).
--   - Pre-SELECT advisory lock: normalises timing between FOUND and NOT FOUND paths
--     (side-channel mitigation, mirrors read_dispute_portal).
--   - Single opaque 42501 for ALL invalid paths: expired / revoked / exhausted /
--     not-found (INV-26 anti-oracle). EXCEPTION WHEN OTHERS re-raises as 42501 so
--     unforeseen internal errors never leak stack information.
--   - NO access_count increment, NO ledger append — read_dispute_portal already
--     tracks access on every call; double-side-effects re-introduce the burn bug.
--   - Whitelist projection: penalty_value_cents + org identity are intentionally
--     disclosed to a tokened anon for branded carrier-facing context. This was
--     the designed contract for InfractionContextProjection (existing Dart model);
--     no new disclosure surface is created here.
--   - service_role intentionally excluded (REVOKE FROM PUBLIC strips it; we do
--     not re-grant — mirrors read_dispute_portal posture per lesson
--     reference_revoke_from_public_strips_service_role).
--
-- Return shape matches InfractionContextProjection.fromJson (Dart):
--   asset_identifier, penalty_value_cents, measured_value, threshold_value,
--   exceeded_by, occurred_at_utc, location_label, record_id,
--   org_display_name, org_cnpj, org_logo_url.
--
-- Invariants: INV-1 (org-scoped via token.organization_id), INV-26 (anti-oracle),
-- INV-22 (tenant isolation via SECURITY DEFINER + token binding).
-- pr_scanner: ignore-regression (Council-approved; see BUG-3 plan)

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
    'org_logo_url',       COALESCE(v_org.logo_url, '')
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

-- ── Grants ────────────────────────────────────────────────────────────────────
-- anon + authenticated only. service_role intentionally omitted: REVOKE FROM PUBLIC
-- strips it (lesson: reference_revoke_from_public_strips_service_role) and we do
-- not re-grant — this is an external carrier-facing function, not a backend tool.
REVOKE ALL ON FUNCTION public.read_infraction_context(UUID) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.read_infraction_context(UUID)
  TO anon, authenticated;
