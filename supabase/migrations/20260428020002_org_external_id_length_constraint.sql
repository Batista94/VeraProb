-- Add DB-level length guard for external_id (mirrors application-layer INV-10 check).
-- 100-char limit is the contract between CRM/ERP integrators and the platform.

ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_external_id_max_length
  CHECK (external_id IS NULL OR char_length(external_id) <= 100);
