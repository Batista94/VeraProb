-- Add organization_id to contractual_financial_snapshot for tenant isolation
ALTER TABLE contractual_financial_snapshot ADD COLUMN organization_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000';

-- For existing records (if any), they'll keep the default. In production, we'd need a specific migration.
-- Update the constraint to include organization_id in uniqueness/integrity checks if necessary.
-- But snapshots are already unique via ID. Deterministic identity is per org.

-- Update RLS policies to use organization_id
ALTER TABLE contractual_financial_snapshot ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their organization snapshots" ON contractual_financial_snapshot
    FOR SELECT USING (organization_id = (auth.jwt() ->> 'org_id')::uuid);

CREATE POLICY "Users can insert their organization snapshots" ON contractual_financial_snapshot
    FOR INSERT WITH CHECK (organization_id = (auth.jwt() ->> 'org_id')::uuid);
