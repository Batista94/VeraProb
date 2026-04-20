-- ==========================================
-- PHASE 2: Contract Rules & Configurable Determinism
-- Creates the Rules Engine schema and deterministic snapshots
-- ==========================================

-- 1. Fixed Taxonomy Enum
CREATE TYPE sla_rule_type AS ENUM (
    'MAX_TOLERANCE_DELAY',
    'MAX_EVIDENCE_GAP',
    'MIN_GEOFENCE_COVERAGE',
    'NO_SHOW_PENALTY'
);

-- 2. Rule Sets Table (Logical grouping for a contract)
CREATE TABLE IF NOT EXISTS contract_rule_sets (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id),
    contract_id TEXT NOT NULL,
    created_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS for rule sets
ALTER TABLE contract_rule_sets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenants can manage their own rule sets"
    ON contract_rule_sets
    FOR ALL
    USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid)
    WITH CHECK (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- 3. Rule Versions Table (Temporal Evolution)
CREATE TABLE IF NOT EXISTS contract_rule_versions (
    id UUID PRIMARY KEY, -- rule_id
    rule_set_id UUID NOT NULL REFERENCES contract_rule_sets(id) ON DELETE CASCADE,
    rule_type sla_rule_type NOT NULL,
    rule_config JSONB NOT NULL,
    rule_version INT NOT NULL,
    evaluation_order INT NOT NULL,
    active_from_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    active_to_utc TIMESTAMPTZ
);

-- JSON Validation Constraints
-- We implement a check constraint to ensure known keys exist based on rule_type
ALTER TABLE contract_rule_versions ADD CONSTRAINT rule_config_schema_check CHECK (
    (rule_type = 'MAX_TOLERANCE_DELAY' AND rule_config ? 'threshold_minutes') OR
    (rule_type = 'MAX_EVIDENCE_GAP' AND rule_config ? 'max_distance_meters') OR
    (rule_type = 'MIN_GEOFENCE_COVERAGE' AND rule_config ? 'min_coverage_pct') OR
    (rule_type = 'NO_SHOW_PENALTY' AND rule_config ? 'multiplier_value')
);

-- RLS for rule versions
ALTER TABLE contract_rule_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenants manage own rule versions"
    ON contract_rule_versions
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM contract_rule_sets
            WHERE id = contract_rule_versions.rule_set_id
            AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM contract_rule_sets
            WHERE id = contract_rule_versions.rule_set_id
            AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
        )
    );

-- 4. Uniqueness and Indexing Safeguards

-- Prevent multiple active versions of the same rule_type within a rule_set
CREATE UNIQUE INDEX idx_unique_active_rule_type 
ON contract_rule_versions (rule_set_id, rule_type) 
WHERE active_to_utc IS NULL;

-- Efficient query for fetching active rules during snapshot generation
CREATE INDEX idx_active_rules_retrieval
ON contract_rule_versions (rule_set_id, active_to_utc);

-- Sort by evaluation order explicitly
CREATE INDEX idx_rule_evaluation_order
ON contract_rule_versions (rule_set_id, evaluation_order);

-- 5. Extend Plan Declarations for Rule Snapshotting
ALTER TABLE plan_declarations ADD COLUMN rule_snapshot_jsonb JSONB;
