# Forensic Test Plan: Seed GTFS Routes
# Migration: 20260816000000_seed_gtfs_routes_for_tenants.sql

## 1. Goal
Ensure the `routes` table contains the GTFS baseline data required by the `_DevSeedButton` for simulating operations, resolving the `42501 insufficient_privilege` error caused by the read-only restriction on tenants (INV-2/INV-22).

## 2. Invariants Addressed
- **INV-2 (Tenant Isolation / Roles):** Routes are system-managed. Dev seeder previously violated this by attempting tenant inserts. Pre-seeding via migration fixes this.
- **INV-3 (Immutability):** Migration relies on `ON CONFLICT DO NOTHING` ensuring zero overwrite of existing reference data.

## 3. Verification Steps
1. Verify `routes` contains exactly 4 reference GTFS routes for each `ACTIVE` organization.
2. Confirm `_DevSeedButton` no longer throws `42501` when attempting to `.insert()` routes, since `exists != null` will intercept the creation attempt.
