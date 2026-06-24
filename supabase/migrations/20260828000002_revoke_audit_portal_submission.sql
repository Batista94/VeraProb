-- INV-DB: zero-downtime-verified
-- The audit_portal_submission RPC is no longer used by the application,
-- as the Snazzy Storm process (single-click dispute resolution) replaced
-- the per-file accept/reject workflow.

DROP FUNCTION IF EXISTS public.audit_portal_submission(uuid, uuid, text, uuid);
