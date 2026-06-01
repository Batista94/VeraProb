-- =============================================================================
-- Migration: CSV idempotent batch-upsert RPCs (Bloco 1D)
-- Timestamp: 20260730000002
--
-- REASON:
--   The Universal CSV Importer must persist validated rows in batch (INV-16 —
--   no row-by-row round trips) and idempotently (re-importing the same ERP
--   export must UPDATE, never duplicate). One SECURITY INVOKER function per
--   operational entity performs a two-phase upsert:
--     Phase 1: rows WITH external_id  → ON CONFLICT (organization_id, external_id)
--     Phase 2: rows WITHOUT external_id → ON CONFLICT (organization_id, <natural key>)
--
-- DESIGN DECISIONS:
--   1. SECURITY INVOKER — RLS of the calling tenant applies (INV-2). The
--      function cannot be used to escape tenant isolation.
--   2. Fail-fast tenant guard: when the caller carries a JWT org claim it MUST
--      equal p_org_id (INV-1). service_role / trusted backend (no JWT org) is
--      allowed to pass p_org_id explicitly; RLS still constrains authenticated
--      callers.
--   3. jsonb_to_recordset for set-based insert — single statement per phase.
--   4. Columns with DB defaults (id, version, status, penalty_multiplier, type,
--      created_at) are omitted on INSERT so the schema owns them.
--
-- SECURITY INVARIANTS:
--   INV-1  organization_id forced to p_org_id on every written row.
--   INV-2  SECURITY INVOKER → RLS enforced for the caller.
--   INV-16 Batch (set-based) upsert, fast connection release.
--   INV-22 No cross-tenant write — guard + RLS + org-scoped conflict keys.
--
-- DB GOVERNANCE:
--   No table DDL. No DROP/DELETE. CREATE OR REPLACE FUNCTION is idempotent.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── Shared tenant guard helper (inlined per function for SECURITY INVOKER) ───
-- (No separate helper function — each RPC inlines the check to keep the
--  invoker security context unambiguous.)

-- ── 1. vehicles ───────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.batch_upsert_vehicles(
  p_org_id uuid,
  p_rows   jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_count   integer := 0;
  v_jwt_org uuid := NULLIF(auth.jwt() -> 'app_metadata' ->> 'org_id', '')::uuid;
BEGIN
  IF v_jwt_org IS NOT NULL AND v_jwt_org <> p_org_id THEN
    RAISE EXCEPTION 'tenant_mismatch' USING ERRCODE = '42501';
  END IF;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, plate text, model text, capacity int, status text
    )
  ), upserted AS (
    INSERT INTO public.vehicles
      (organization_id, plate, model, capacity, status, external_id)
    SELECT p_org_id, plate, model, COALESCE(capacity, 0),
           COALESCE(status, 'available'), external_id
    FROM src WHERE external_id IS NOT NULL
    ON CONFLICT (organization_id, external_id) WHERE external_id IS NOT NULL
    DO UPDATE SET plate = EXCLUDED.plate, model = EXCLUDED.model,
                  capacity = EXCLUDED.capacity, status = EXCLUDED.status,
                  updated_at = NOW()
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM upserted;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, plate text, model text, capacity int, status text
    )
  ), upserted AS (
    INSERT INTO public.vehicles
      (organization_id, plate, model, capacity, status)
    SELECT p_org_id, plate, model, COALESCE(capacity, 0),
           COALESCE(status, 'available')
    FROM src WHERE external_id IS NULL
    ON CONFLICT (organization_id, plate)
    DO UPDATE SET model = EXCLUDED.model, capacity = EXCLUDED.capacity,
                  status = EXCLUDED.status, updated_at = NOW()
    RETURNING 1
  )
  SELECT v_count + count(*) INTO v_count FROM upserted;

  RETURN v_count;
END;
$$;

-- ── 2. drivers ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.batch_upsert_drivers(
  p_org_id uuid,
  p_rows   jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_count   integer := 0;
  v_jwt_org uuid := NULLIF(auth.jwt() -> 'app_metadata' ->> 'org_id', '')::uuid;
BEGIN
  IF v_jwt_org IS NOT NULL AND v_jwt_org <> p_org_id THEN
    RAISE EXCEPTION 'tenant_mismatch' USING ERRCODE = '42501';
  END IF;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, full_name text, license_number text, status text
    )
  ), upserted AS (
    INSERT INTO public.drivers
      (organization_id, full_name, license_number, status, external_id)
    SELECT p_org_id, full_name, license_number,
           COALESCE(status, 'active'), external_id
    FROM src WHERE external_id IS NOT NULL
    ON CONFLICT (organization_id, external_id) WHERE external_id IS NOT NULL
    DO UPDATE SET full_name = EXCLUDED.full_name,
                  license_number = EXCLUDED.license_number,
                  status = EXCLUDED.status, updated_at = NOW()
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM upserted;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, full_name text, license_number text, status text
    )
  ), upserted AS (
    INSERT INTO public.drivers
      (organization_id, full_name, license_number, status)
    SELECT p_org_id, full_name, license_number, COALESCE(status, 'active')
    FROM src WHERE external_id IS NULL
    ON CONFLICT (organization_id, license_number)
    DO UPDATE SET full_name = EXCLUDED.full_name,
                  status = EXCLUDED.status, updated_at = NOW()
    RETURNING 1
  )
  SELECT v_count + count(*) INTO v_count FROM upserted;

  RETURN v_count;
END;
$$;

-- ── 3. contractors ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.batch_upsert_contractors(
  p_org_id uuid,
  p_rows   jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_count   integer := 0;
  v_jwt_org uuid := NULLIF(auth.jwt() -> 'app_metadata' ->> 'org_id', '')::uuid;
BEGIN
  IF v_jwt_org IS NOT NULL AND v_jwt_org <> p_org_id THEN
    RAISE EXCEPTION 'tenant_mismatch' USING ERRCODE = '42501';
  END IF;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, name text, tax_id text,
      primary_email text, contact_name text
    )
  ), upserted AS (
    INSERT INTO public.contractors
      (organization_id, name, tax_id, primary_email, contact_name, external_id)
    SELECT p_org_id, name, tax_id, primary_email, contact_name, external_id
    FROM src WHERE external_id IS NOT NULL
    ON CONFLICT (organization_id, external_id) WHERE external_id IS NOT NULL
    DO UPDATE SET name = EXCLUDED.name, tax_id = EXCLUDED.tax_id,
                  primary_email = EXCLUDED.primary_email,
                  contact_name = EXCLUDED.contact_name
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM upserted;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, name text, tax_id text,
      primary_email text, contact_name text
    )
  ), upserted AS (
    INSERT INTO public.contractors
      (organization_id, name, tax_id, primary_email, contact_name)
    SELECT p_org_id, name, tax_id, primary_email, contact_name
    FROM src WHERE external_id IS NULL
    ON CONFLICT (organization_id, name)
    DO UPDATE SET tax_id = EXCLUDED.tax_id,
                  primary_email = EXCLUDED.primary_email,
                  contact_name = EXCLUDED.contact_name
    RETURNING 1
  )
  SELECT v_count + count(*) INTO v_count FROM upserted;

  RETURN v_count;
END;
$$;

-- ── 4. contracts ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.batch_upsert_contracts(
  p_org_id uuid,
  p_rows   jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_count   integer := 0;
  v_jwt_org uuid := NULLIF(auth.jwt() -> 'app_metadata' ->> 'org_id', '')::uuid;
BEGIN
  IF v_jwt_org IS NOT NULL AND v_jwt_org <> p_org_id THEN
    RAISE EXCEPTION 'tenant_mismatch' USING ERRCODE = '42501';
  END IF;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, name text, contractor_name text,
      valid_from_utc timestamptz, valid_until_utc timestamptz
    )
  ), upserted AS (
    INSERT INTO public.contracts
      (organization_id, name, contractor_name,
       valid_from_utc, valid_until_utc, external_id)
    SELECT p_org_id, name, contractor_name,
           valid_from_utc, valid_until_utc, external_id
    FROM src WHERE external_id IS NOT NULL
    ON CONFLICT (organization_id, external_id) WHERE external_id IS NOT NULL
    DO UPDATE SET name = EXCLUDED.name,
                  contractor_name = EXCLUDED.contractor_name,
                  valid_from_utc = EXCLUDED.valid_from_utc,
                  valid_until_utc = EXCLUDED.valid_until_utc
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM upserted;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, name text, contractor_name text,
      valid_from_utc timestamptz, valid_until_utc timestamptz
    )
  ), upserted AS (
    INSERT INTO public.contracts
      (organization_id, name, contractor_name, valid_from_utc, valid_until_utc)
    SELECT p_org_id, name, contractor_name, valid_from_utc, valid_until_utc
    FROM src WHERE external_id IS NULL
    ON CONFLICT (organization_id, name, valid_from_utc)
    DO UPDATE SET contractor_name = EXCLUDED.contractor_name,
                  valid_until_utc = EXCLUDED.valid_until_utc
    RETURNING 1
  )
  SELECT v_count + count(*) INTO v_count FROM upserted;

  RETURN v_count;
END;
$$;

-- ── 5. operational_zones ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.batch_upsert_operational_zones(
  p_org_id uuid,
  p_rows   jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_count   integer := 0;
  v_jwt_org uuid := NULLIF(auth.jwt() -> 'app_metadata' ->> 'org_id', '')::uuid;
BEGIN
  IF v_jwt_org IS NOT NULL AND v_jwt_org <> p_org_id THEN
    RAISE EXCEPTION 'tenant_mismatch' USING ERRCODE = '42501';
  END IF;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, name text, latitude double precision,
      longitude double precision, radius_meters int, type text
    )
  ), upserted AS (
    INSERT INTO public.operational_zones
      (organization_id, name, latitude, longitude, radius_meters, type, external_id)
    SELECT p_org_id, name, latitude, longitude, radius_meters,
           COALESCE(type, 'garagem'), external_id
    FROM src WHERE external_id IS NOT NULL
    ON CONFLICT (organization_id, external_id) WHERE external_id IS NOT NULL
    DO UPDATE SET name = EXCLUDED.name, latitude = EXCLUDED.latitude,
                  longitude = EXCLUDED.longitude,
                  radius_meters = EXCLUDED.radius_meters, type = EXCLUDED.type
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM upserted;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, name text, latitude double precision,
      longitude double precision, radius_meters int, type text
    )
  ), upserted AS (
    INSERT INTO public.operational_zones
      (organization_id, name, latitude, longitude, radius_meters, type)
    SELECT p_org_id, name, latitude, longitude, radius_meters,
           COALESCE(type, 'garagem')
    FROM src WHERE external_id IS NULL
    ON CONFLICT (organization_id, name)
    DO UPDATE SET latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude,
                  radius_meters = EXCLUDED.radius_meters, type = EXCLUDED.type
    RETURNING 1
  )
  SELECT v_count + count(*) INTO v_count FROM upserted;

  RETURN v_count;
END;
$$;

-- ── Grants (INV-DATA-API-GRANT) ──────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION public.batch_upsert_vehicles(uuid, jsonb)          TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.batch_upsert_drivers(uuid, jsonb)           TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.batch_upsert_contractors(uuid, jsonb)       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.batch_upsert_contracts(uuid, jsonb)         TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.batch_upsert_operational_zones(uuid, jsonb) TO authenticated, service_role;
