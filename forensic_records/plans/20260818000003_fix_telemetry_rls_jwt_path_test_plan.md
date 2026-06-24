# Forensic Test Plan: Fix Telemetry JWT Path
# Migration: 20260818000003_fix_telemetry_rls_jwt_path.sql

## 1. Goal
Ensure that `raw_telemetry_payloads` and `canonical_facts` evaluate RLS correctly by utilizing the standard `auth.jwt() -> 'app_metadata' ->> 'org_id'` path defined by INV-2, instead of the erroneous `auth.jwt() ->> 'organization_id'`.

## 2. Invariants Addressed
- **INV-2 (Tenant Isolation / JWT Structure):** The system relies on custom JWT claims populated by GoTrue hooks (`app_metadata.org_id`). The previous policy queried a non-existent claim, defaulting to NULL and blocking valid inserts.

## 3. Verification Steps
1. Verify that `raw_telemetry_payloads` RLS policy `raw_telemetry_payloads_org_isolation` uses the correct `app_metadata` path.
2. Verify that `canonical_facts` RLS policy `canonical_facts_org_isolation` uses the correct `app_metadata` path.
