-- =============================================================================
-- Phase 10: Add allowed_domains to organizations
-- =============================================================================
-- Stores a whitelist of lowercase email domain suffixes per organization.
-- Used for: SSO routing (Entra ID / Google), auto-join provisioning,
-- and identity injection prevention.
--
-- INV-2: authenticated role has no UPDATE policy on this column → DENY.
--        SuperAdmin writes go via super_admin_update_allowed_domains RPC
--        (SECURITY DEFINER, validates super_admin JWT claim).
-- INV-7: text[] in DB → List<String> in Dart. Strict types.
--
-- Normalization contract (enforced at application layer):
--   All entries stored lowercase and deduplicated. The RPC and the
--   Dart repository both normalize before persisting.
-- =============================================================================

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS allowed_domains text[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.organizations.allowed_domains IS
  'Lowercase email domain whitelist for SSO routing, auto-join, and identity injection prevention. SuperAdmin-only write via SECURITY DEFINER RPC. Stored normalized (lowercase, deduplicated).';
