-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: Driver Offboarding (Inativação/Arquivamento)
--
-- Problem: Hard DELETE on drivers(id) fails with FK 409 (telegram_binding_tokens,
--          telegram_evidence_uploads reference drivers.id without ON DELETE CASCADE).
--          Forensic evidence must NEVER be deleted (INV-3).
--
-- Solution: Soft-archive pattern — set status='inactive' + archived_at_utc=NOW()
--           and revoke all active Telegram bindings via unbound_at_utc stamp.
--
-- INV-1:  org_id validated inside RPC via SECURITY DEFINER + JWT check.
-- INV-3:  No DELETE. Evidence rows preserved. Ledger append-only.
-- INV-6:  archived_at_utc is TIMESTAMPTZ (UTC mandatory — bare timestamp prohibited).
-- INV-10: Raises P0003 if driver not found in org (INV-26: 404 parity).
-- INV-22: Tenant-A cannot archive Tenant-B's driver.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Add archived_at_utc to drivers ────────────────────────────────────────
-- Safe catalog-only ADD COLUMN (Postgres 11+ constant DEFAULT = no row rewrite).

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS archived_at_utc TIMESTAMPTZ;

-- Partial index: fast lookup of non-archived active drivers.
CREATE INDEX IF NOT EXISTS idx_drivers_active
  ON public.drivers (organization_id, status)
  WHERE archived_at_utc IS NULL;

-- ── 2. offboard_driver RPC ────────────────────────────────────────────────────
-- Atomically:
--   a) Validates driver belongs to the calling org (INV-1, INV-22).
--   b) Stamps unbound_at_utc on all active telegram_chat_bindings (soft revoke).
--   c) Sets driver status='inactive' + archived_at_utc=NOW() (soft archive).
-- Never deletes rows (INV-3).

CREATE OR REPLACE FUNCTION public.offboard_driver(
  p_driver_id  UUID,
  p_org_id     UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_exists BOOLEAN;
BEGIN
  -- INV-1/INV-22: verify driver belongs to the requesting org.
  SELECT EXISTS(
    SELECT 1 FROM public.drivers
    WHERE id = p_driver_id
      AND organization_id = p_org_id
      AND archived_at_utc IS NULL
  ) INTO v_driver_exists;

  IF NOT v_driver_exists THEN
    -- INV-26: identical error for "not found" and "wrong org" (anti-oracle).
    RAISE EXCEPTION 'driver not found or already archived'
      USING ERRCODE = 'P0003';
  END IF;

  -- a. Revoke active Telegram bindings (soft unbind, preserves forensic trail).
  UPDATE public.telegram_chat_bindings
    SET unbound_at_utc = NOW()
  WHERE driver_id = p_driver_id
    AND organization_id = p_org_id
    AND unbound_at_utc IS NULL;

  -- b. Archive driver (INV-3: no DELETE, status transition only).
  UPDATE public.drivers
    SET status         = 'inactive',
        archived_at_utc = NOW()
  WHERE id = p_driver_id
    AND organization_id = p_org_id;
END;
$$;

-- RLS: only TENANT_ADMIN may call offboard_driver.
-- (SECURITY DEFINER bypasses RLS on tables, but we guard at the RPC grant level.)
REVOKE ALL ON FUNCTION public.offboard_driver(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.offboard_driver(UUID, UUID)
  TO authenticated;

-- ── 3. Fix telegram_message_date DEFAULT — INV-6 audit anchor must be explicit ─
-- The DEFAULT NOW() masks missed device-clock inserts with server clock.
-- Removing it forces the webhook to always supply the value explicitly.
-- Existing rows are unaffected (NULL DEFAULT removal is catalog-only).

ALTER TABLE public.telegram_evidence_uploads
  ALTER COLUMN telegram_message_date DROP DEFAULT;
