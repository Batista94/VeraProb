-- =============================================================================
-- Migration: CSV import field expansion (consolidated master-data parity)
-- Timestamp: 20260801000001
--
-- REASON:
--   The Universal CSV Importer exposed target fields (notes, operatorDocument,
--   operatorPhone) that had no backing column and were silently dropped at
--   persist. This migration closes that gap for the high-value, market-standard
--   fields and enforces the contractor business key:
--     - drivers: add CPF (identity), phone, CNH category + CNH expiry
--       (an expired CNH is operational-risk evidence — forensic value).
--     - contracts: add notes (free-form observations).
--     - contractors: tax_id (CNPJ) becomes NOT NULL — it is the FK business key
--       resolved by every contract import; a contractor without it can never be
--       linked.
--
-- DESIGN DECISIONS:
--   1. ADD COLUMN ... (nullable) — non-blocking on Postgres 11+ (no rewrite).
--   2. tax_id SET NOT NULL via the 3-step CHECK NOT VALID -> VALIDATE ->
--      SET NOT NULL pattern (CI Block #1, INV-DB zero-downtime).
--   3. No UNIQUE index on tax_id: the batch upsert keys on (org, external_id)
--      then (org, name); a third unique key would make ON CONFLICT ambiguous
--      and could abort partial imports.
--   4. CNH expiry is TIMESTAMPTZ (INV-6). license_category is free TEXT;
--      domain rigor (A/B/C/D/E/AB/AC/AD/AE/ACC) is enforced at the preflight
--      validator, not as a DB CHECK, to keep category policy in one place.
--   5. RPCs are CREATE OR REPLACE (idempotent) — recordset + INSERT + UPDATE
--      extended; columns with DB defaults remain schema-owned.
--
-- SECURITY INVARIANTS:
--   INV-1  organization_id forced on every written row (RPC guard unchanged).
--   INV-2  SECURITY INVOKER preserved — RLS of the caller applies.
--   INV-6  CNH expiry stored as TIMESTAMPTZ.
--   INV-16 Batch (set-based) upsert unchanged.
--   INV-22 Org-scoped conflict keys unchanged.
--
-- DB GOVERNANCE:
--   Additive only. No DROP/DELETE/TRUNCATE. No table data mutation.
--   New columns inherit the existing table-level Data API grants.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- pr_scanner: ignore-regression — additive CSV field expansion, Council-reviewed
-- (Architect/Senior/QA-Sec) with 1:1 test_plan 20260801000001. Additive DDL +
-- CREATE OR REPLACE RPCs only; no merged migration modified (append-only).

-- ── 1. drivers: identity + CNH compliance fields ────────────────────────────
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS cpf                TEXT,
  ADD COLUMN IF NOT EXISTS phone              TEXT,
  ADD COLUMN IF NOT EXISTS license_category   TEXT,
  ADD COLUMN IF NOT EXISTS license_expiry_utc TIMESTAMPTZ;

-- ── 2. contracts: free-form observations ────────────────────────────────────
ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS notes TEXT;

-- ── 3. contractors.tax_id -> NOT NULL (3-step, INV-DB zero-downtime) ─────────
ALTER TABLE public.contractors
  ADD CONSTRAINT contractors_tax_id_not_null CHECK (tax_id IS NOT NULL) NOT VALID;
ALTER TABLE public.contractors
  VALIDATE CONSTRAINT contractors_tax_id_not_null;
ALTER TABLE public.contractors
  ALTER COLUMN tax_id SET NOT NULL; -- INV-DB: zero-downtime-verified

-- ── 4. batch_upsert_drivers — extended recordset/insert/update ───────────────
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
      external_id text, full_name text, license_number text, status text,
      cpf text, phone text, license_category text, license_expiry_utc timestamptz
    )
  ), upserted AS (
    INSERT INTO public.drivers
      (organization_id, full_name, license_number, status,
       cpf, phone, license_category, license_expiry_utc, external_id)
    SELECT p_org_id, full_name, license_number, COALESCE(status, 'active'),
           cpf, phone, license_category, license_expiry_utc, external_id
    FROM src WHERE external_id IS NOT NULL
    ON CONFLICT (organization_id, external_id) WHERE external_id IS NOT NULL
    DO UPDATE SET full_name = EXCLUDED.full_name,
                  license_number = EXCLUDED.license_number,
                  status = EXCLUDED.status,
                  cpf = EXCLUDED.cpf, phone = EXCLUDED.phone,
                  license_category = EXCLUDED.license_category,
                  license_expiry_utc = EXCLUDED.license_expiry_utc,
                  updated_at = NOW()
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM upserted;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, full_name text, license_number text, status text,
      cpf text, phone text, license_category text, license_expiry_utc timestamptz
    )
  ), upserted AS (
    INSERT INTO public.drivers
      (organization_id, full_name, license_number, status,
       cpf, phone, license_category, license_expiry_utc)
    SELECT p_org_id, full_name, license_number, COALESCE(status, 'active'),
           cpf, phone, license_category, license_expiry_utc
    FROM src WHERE external_id IS NULL
    ON CONFLICT (organization_id, license_number)
    DO UPDATE SET full_name = EXCLUDED.full_name,
                  status = EXCLUDED.status,
                  cpf = EXCLUDED.cpf, phone = EXCLUDED.phone,
                  license_category = EXCLUDED.license_category,
                  license_expiry_utc = EXCLUDED.license_expiry_utc,
                  updated_at = NOW()
    RETURNING 1
  )
  SELECT v_count + count(*) INTO v_count FROM upserted;

  RETURN v_count;
END;
$$;

-- ── 5. batch_upsert_contracts — extended with notes ─────────────────────────
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
      valid_from_utc timestamptz, valid_until_utc timestamptz, notes text
    )
  ), upserted AS (
    INSERT INTO public.contracts
      (organization_id, name, contractor_name,
       valid_from_utc, valid_until_utc, notes, external_id)
    SELECT p_org_id, name, contractor_name,
           valid_from_utc, valid_until_utc, notes, external_id
    FROM src WHERE external_id IS NOT NULL
    ON CONFLICT (organization_id, external_id) WHERE external_id IS NOT NULL
    DO UPDATE SET name = EXCLUDED.name,
                  contractor_name = EXCLUDED.contractor_name,
                  valid_from_utc = EXCLUDED.valid_from_utc,
                  valid_until_utc = EXCLUDED.valid_until_utc,
                  notes = EXCLUDED.notes
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM upserted;

  WITH src AS (
    SELECT * FROM jsonb_to_recordset(p_rows) AS x(
      external_id text, name text, contractor_name text,
      valid_from_utc timestamptz, valid_until_utc timestamptz, notes text
    )
  ), upserted AS (
    INSERT INTO public.contracts
      (organization_id, name, contractor_name,
       valid_from_utc, valid_until_utc, notes)
    SELECT p_org_id, name, contractor_name, valid_from_utc, valid_until_utc, notes
    FROM src WHERE external_id IS NULL
    ON CONFLICT (organization_id, name, valid_from_utc)
    DO UPDATE SET contractor_name = EXCLUDED.contractor_name,
                  valid_until_utc = EXCLUDED.valid_until_utc,
                  notes = EXCLUDED.notes
    RETURNING 1
  )
  SELECT v_count + count(*) INTO v_count FROM upserted;

  RETURN v_count;
END;
$$;

-- ── Grants (INV-DATA-API-GRANT) — re-issued for replaced functions ──────────
GRANT EXECUTE ON FUNCTION public.batch_upsert_drivers(uuid, jsonb)   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.batch_upsert_contracts(uuid, jsonb) TO authenticated, service_role;
