# Supabase Database Bootstrap & Migration Runbook

This document outlines the procedure for initializing and migrating the PactaFlow database in a Supabase Cloud environment.

## 1. Initial State
The database begins with the core schema defined in `supabase/migrations/initial_schema.sql` (if applicable) or the base tables for SLA Audit.

## 2. Migration Sequence
Migrations must be applied sequentially to ensure referential integrity and proper RLS setup.

### Phase 1: Multi-Tenancy Foundation
**File:** `supabase/migrations/20260305171000_multi_tenancy_foundation.sql`
- Creates `organizations` table.
- Creates `user_roles` table for RBAC.
- Replaces/Migrates ledger and projections to `_v2` versions with `organization_id` HASH partitioning.
- Injects JWT custom claims hook.
- Enforces strict RLS policies.

### Phase 2: Contract Rules Engine
**File:** `supabase/migrations/20260305175500_contract_rules.sql`
- Creates `sla_rule_type` ENUM.
- Creates `contract_rule_sets` and `contract_rule_versions` tables.
- Adds `rule_snapshot_jsonb` to `plan_declarations`.
- Applies RLS to rule tables.

## 3. Execution Procedure (Manual Cloud Migration)
Since the Supabase CLI may not be authenticated to the remote Cloud project in all environments, follow these steps:

1. Open the [Supabase Dashboard](https://supabase.com/dashboard).
2. Navigate to your Project -> **SQL Editor**.
3. Create a **New Query**.
4. Copy the contents of the migration file.
5. Paste into the SQL Editor.
6. Click **Run**.
7. Verify success in the output console.

## 4. Disaster Recovery & Reset
- **WARNING:** Do not use `supabase db reset` against a production/cloud instance as it is destructive.
- For local development, use `npx supabase db reset`.
- In Cloud, data is immutable in the ledger. To "reset" a tenant's state, use a new `organization_id` or `contract_id`.

## 5. Verification
After migration, run the following query to verify RLS is active:
```sql
SELECT * FROM pg_policies WHERE schemaname = 'public';
```
Ensure all tables have `TRUE` in the `enabled` column for RLS.
