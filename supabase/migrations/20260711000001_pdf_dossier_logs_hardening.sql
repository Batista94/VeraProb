-- pr_scanner: ignore-regression
-- Phase 10.4.B — Bloco 2 Hardening: pdf_dossier_logs append-only enforcement
-- INV-3:  APPEND-ONLY — REVOKE UPDATE, DELETE from authenticated + anon
-- INV-15: Idempotency — UNIQUE constraint prevents duplicate log entries on replay
-- INV-DB: Non-destructive ADD CONSTRAINT only (no DROP/ALTER SET NOT NULL)

-- ── INV-3: Prevent mutation of forensic audit trail ────────────────────────

REVOKE UPDATE, DELETE ON public.pdf_dossier_logs FROM authenticated, anon;

-- ── INV-15: Idempotency guard — no duplicate hashes per entry ─────────────
-- A given (org, ledger_entry, hash) triple must be unique:
-- same PDF bytes on replay → same hash → ON CONFLICT DO NOTHING is safe.

ALTER TABLE public.pdf_dossier_logs
  ADD CONSTRAINT uq_pdf_dossier_logs_entry_hash
    UNIQUE (organization_id, sla_ledger_entry_id, document_hash_sha256);
