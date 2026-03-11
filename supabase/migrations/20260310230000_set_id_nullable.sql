-- Migration: Make set_id nullable in sla_audit_ledger_v2
-- Root cause: The entity_id was renamed to set_id but retained the NOT NULL constraint.
-- However, certain ledger events like CONTRACT_CREATED are emitted before any sets are declared,
-- so they legitimately have a null set_id.

ALTER TABLE public.sla_audit_ledger_v2 ALTER COLUMN set_id DROP NOT NULL;
