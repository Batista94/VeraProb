# Test Plan: 20260822000002_fix_location_label_regression.sql

**Governing Migration:** `supabase/migrations/20260822000002_fix_location_label_regression.sql`
**Companion pgTAP:** `supabase/tests/20260822000002_fix_location_label_regression_test.sql`
**Invariants Checked:** INV-1, INV-22, INV-26

## Problem Fixed

Migration `20260821000001_enhance_infraction_context_rpc.sql` added `primary_evidence_lat`, `primary_evidence_lng`, and `clause_ref` fields to `read_infraction_context` but accidentally collapsed the `location_label` COALESCE priority to a lat,lng-only fallback. This regressed the priority chain (`geofence_name → address → location_label → lat,lng`) that was originally established by `20260820000003`.

This migration restores the correct four-level COALESCE while preserving all fields added by `20260821000001`.

## Scenarios

1. **T1: geofence_name priority (INV-1)**
   - Condition: `verdict_evidence` contains `geofence_name`, `address`, and `location_label`.
   - Expected: `location_label` field in response = `geofence_name` value.

2. **T2: address fallback**
   - Condition: `verdict_evidence` has `address` and `location_label` but no `geofence_name`.
   - Expected: `location_label` field in response = `address` value.

3. **T3: location_label fallback**
   - Condition: `verdict_evidence` has `location_label` but neither `geofence_name` nor `address`.
   - Expected: `location_label` field in response = `location_label` value.

4. **T4: lat,lng ultimate fallback**
   - Condition: `verdict_evidence` has only `primary_evidence_lat` and `primary_evidence_lng`.
   - Expected: `location_label` field in response = `lat,lng` concatenated string.

## Go/No-Go Gate

All four COALESCE priority assertions must return `is()` PASS before merge to main.
