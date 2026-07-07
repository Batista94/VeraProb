-- =============================================================================
-- pr_scanner: ignore-regression
-- 20260914000001_categorize_dispute_reason_codes.sql
-- Context: Updates applies_to column in dispute_reason_codes based on action type
-- Invariants: INV-DB (Append-Only), INV-22 (Global Catalog)
-- =============================================================================

-- 1. Update existing resolution-specific codes
UPDATE public.dispute_reason_codes
SET applies_to = 'RESOLUTION'
WHERE code IN (
  'FORCE_MAJEURE',
  'SENSOR_FAULT',
  'GPS_SIGNAL_LOSS',
  'ROUTE_DEVIATION',
  'WEATHER_EVENT',
  'TRAFFIC_INCIDENT',
  'ASSET_BREAKDOWN',
  'OPERATOR_EMERGENCY',
  'REGULATORY_INTERVENTION',
  'COMMUNICATION_FAILURE',
  'THIRD_PARTY_INCIDENT',
  'INFRASTRUCTURE_FAULT'
) AND applies_to = 'ALL';

-- 2. Insert specific REJECTION codes (since the initial seed lacked them)
INSERT INTO public.dispute_reason_codes
  (code, category, label_pt, label_en, applies_to, is_custom) VALUES
  ('INSUFFICIENT_EVIDENCE', 'OPERATIONAL', 'Evidência Insuficiente', 'Insufficient Evidence', 'REJECTION', FALSE),
  ('POLICY_VIOLATION_CONFIRMED', 'CONTRACTUAL', 'Violação de Política Confirmada', 'Policy Violation Confirmed', 'REJECTION', FALSE)
ON CONFLICT (code, organization_id) DO NOTHING;
