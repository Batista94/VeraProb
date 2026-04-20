-- Phase 9.5: Add transport vertical to SLA templates
-- Nullable for backward compatibility with existing templates.
ALTER TABLE sla_templates ADD COLUMN IF NOT EXISTS vertical TEXT;
