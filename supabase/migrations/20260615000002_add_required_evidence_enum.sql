-- =============================================================================
-- Migration: Pre-seed REQUIRED_EVIDENCE enum value
--
-- ALTER TYPE ... ADD VALUE is non-transactional in Postgres — the new value
-- is only visible to CHECK constraints after a transaction commit.
-- This migration runs in its own transaction (before 20260616) so the value
-- is committed and visible when the constraint is created.
-- =============================================================================

ALTER TYPE sla_rule_type ADD VALUE IF NOT EXISTS 'REQUIRED_EVIDENCE';
