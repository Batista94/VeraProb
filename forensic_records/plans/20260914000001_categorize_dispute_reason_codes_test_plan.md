# Test Plan: 20260914000001_categorize_dispute_reason_codes

## Objective
Verify that the `dispute_reason_codes` table is correctly updated to classify specific codes as `RESOLUTION` and new codes as `REJECTION`.

## Pre-conditions
- The `dispute_reason_codes` table exists.
- The default seed is loaded (codes are `ALL`).

## Test Cases

### 1. Resolution Categorization
- **Action:** Query codes that should have been updated to `RESOLUTION` (e.g., `SENSOR_FAULT`, `WEATHER_EVENT`).
- **Assertion:** `applies_to` equals `RESOLUTION`.

### 2. Rejection Insertion
- **Action:** Query the newly inserted codes (`INSUFFICIENT_EVIDENCE`, `POLICY_VIOLATION_CONFIRMED`).
- **Assertion:** `applies_to` equals `REJECTION`.

### 3. Unaffected Codes
- **Action:** Query codes that were not updated (e.g., `CONTRACT_EXCEPTION`, `OTHER`).
- **Assertion:** `applies_to` equals `ALL`.

## Environment
- **DB:** pgTAP via `make test-db`
