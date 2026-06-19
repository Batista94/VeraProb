-- Suppress DROP/CREATE NOTICEs on fresh reset.
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: dispute-portal append-only DELETE triggers must honor the
--            test-cleanup GUC (vera.authorized_test_cleanup).
--
-- 20260822000003 reordered test_cleanup_forensic_data to delete FK-child portal
-- tables before sanction_review_queue. But the six append-only DELETE triggers
-- guarding those tables (prevent_dpt/dea/sack/pes/pjs/sel_delete) RAISE
-- unconditionally — they never check the GUC the cleanup RPC sets
-- (SET LOCAL vera.authorized_test_cleanup = 'on'). Result: the very first
-- child DELETE with a live row throws 23001/restrict_violation, so tearDownAll
-- cleanup fails and sanction_review_queue is never emptied.
--
-- Fix: mirror the canonical pattern from 20260423180000_forensic_test_hardening
-- (prevent_tel_delete et al.) — RETURN OLD when the maintenance GUC is set;
-- otherwise keep the existing append-only block (message + errcode unchanged).
-- Production paths never set the GUC, so immutability is preserved (INV-3).
-- Functions are replaced in place; triggers already bound to them are untouched.
-- INV-3, INV-1, INV-2, INV-22.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.prevent_dpt_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('vera.authorized_test_cleanup', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION
    'dispute_portal_tokens is append-only (INV-3). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_dea_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('vera.authorized_test_cleanup', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION
    'dispute_evidence_attachments is append-only. Use soft-delete (deleted_at). id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_sack_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('vera.authorized_test_cleanup', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION
    'sanction_acknowledgements is append-only (INV-3). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_pes_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('vera.authorized_test_cleanup', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION
    'portal_evidence_submissions is append-only. Use soft-delete (deleted_at). id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_pjs_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('vera.authorized_test_cleanup', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION
    'portal_justification_submissions is append-only. Use soft-delete (deleted_at). id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_sel_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('vera.authorized_test_cleanup', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION
    'sanction_escalation_log is immutable (INV-1). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

RESET client_min_messages;
