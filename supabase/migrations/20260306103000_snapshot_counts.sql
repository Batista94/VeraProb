-- Phase 5: Reporting & Financial Exports
-- Add obligation counts to financial snapshots

ALTER TABLE contractual_financial_snapshot
ADD COLUMN total_obligations INTEGER NOT NULL DEFAULT 0,
ADD COLUMN executed_count INTEGER NOT NULL DEFAULT 0,
ADD COLUMN no_show_count INTEGER NOT NULL DEFAULT 0,
ADD COLUMN evidence_gap_count INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN contractual_financial_snapshot.total_obligations IS 'Total number of obligations evaluated for this operational day.';
COMMENT ON COLUMN contractual_financial_snapshot.executed_count IS 'Number of successfully executed obligations.';
COMMENT ON COLUMN contractual_financial_snapshot.no_show_count IS 'Number of obligations resulting in No Show.';
COMMENT ON COLUMN contractual_financial_snapshot.evidence_gap_count IS 'Number of obligations with Evidence Gap.';
