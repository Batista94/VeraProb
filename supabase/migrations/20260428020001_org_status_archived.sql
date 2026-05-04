-- Add ARCHIVED to organizations status CHECK constraint.
-- ARCHIVED = data preserved read-only; DELETED = GDPR hard-remove.
-- INV-3: No destructive alter — drop+add constraint only.

ALTER TABLE public.organizations
  DROP CONSTRAINT IF EXISTS organizations_status_check;

ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_status_check
  CHECK (status IN ('TRIAL','ACTIVE','SUSPENDED','CHURNED','ARCHIVED','DELETED'));

COMMENT ON COLUMN public.organizations.status IS
  'Lifecycle: TRIAL→ACTIVE→SUSPENDED→CHURNED→ARCHIVED. DELETED = GDPR hard-remove. ARCHIVED = read-only, all API secrets revoked.';
