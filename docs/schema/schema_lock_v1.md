# VeraProb — Schema Lock v1

**Locked:** 2026-03-24
**Phase:** 10.1 — Schema Lock & Migration Freeze
**Gate:** `READY FOR FIRST TENANT`
**Audit baseline:** 67 migrations · 26 tables · 0 critical violations

This document is an **immutable snapshot** of the production schema at the Phase 10 freeze point.
No new migrations may be merged to `main` without explicit PO sign-off and Lead Reviewer [GO].

---

## Migration Inventory

| # | Filename | Purpose |
|---|---|---|
| 1 | 20200101000000_enable_extensions.sql | Enable pgcrypto, uuid-ossp |
| 2 | 20260101000000_base_schema.sql | Core domain tables |
| 3 | 20260304195300_sla_audit_hardening.sql | Ledger immutability (INV-1) |
| 4 | 20260305171000_multi_tenancy_foundation.sql | RLS foundation (INV-6) |
| 5 | 20260305175500_contract_rules.sql | Contract rules + RLS |
| 6 | 20260305194500_explainability_traces.sql | EvaluationDecision traces (INV-23) |
| 7 | 20260305214500_operational_alerts.sql | Operational alert table |
| 8 | 20260306103000_snapshot_counts.sql | Financial snapshot counts |
| 9 | 20260306103100_snapshot_org_id.sql | Add org_id to snapshots |
| 10 | 20260310000000_contract_lifecycle.sql | Contract lifecycle states |
| 11 | 20260310180000_core_schema_recovery.sql | Schema recovery / corrections |
| 12 | 20260310190000_fix_rls_recovery_tables.sql | RLS fix: recovery tables |
| 13 | 20260310200000_fix_contracts_rls_jwt_path.sql | JWT path fix: contracts |
| 14 | 20260310210000_fix_rls_jwt_paths_and_missing_columns.sql | JWT path unification (partial) |
| 15 | 20260310220000_schema_sync_dart_domain.sql | Sync schema with Dart domain |
| 16 | 20260310230000_set_id_nullable.sql | Nullable id adjustment |
| 17 | 20260310240000_contracts_financial_ceiling.sql | Financial ceiling column |
| 18 | 20260311000000_b2b_refactoring_foundation.sql | B2B model refactoring |
| 19 | 20260311000001_fix_drivers_trips_rls_jwt_path.sql | JWT path fix: drivers/trips |
| 20 | 20260311000002_operational_zone_business_fields.sql | Zone business fields |
| 21 | 20260311000003_operational_zones_add_created_at.sql | created_at on zones |
| 22 | 20260312000001_sla_templates.sql | SLA template tables |
| 23 | 20260312000002_contracts_clone_field.sql | Clone field on contracts |
| 24 | 20260312000003_operational_zones_contractor_label.sql | Contractor label on zones |
| 25 | 20260315000001_zone_scope.sql | Zone scope column |
| 26 | 20260316000001_cse_rls_fix.sql | RLS fix: contractual_service_executions |
| 27 | 20260317000001_rls_jwt_path_unification.sql | **Canonical JWT path unification** |
| 28 | 20260317000002_organizations_enrichment.sql | Org enrichment fields |
| 29 | 20260317000003_fix_jwt_hook_null_safety.sql | JWT hook null safety |
| 30 | 20260318000001_contractors_table.sql | Contractors table |
| 31 | 20260318000002_zones_contractor_fk.sql | Zones → contractors FK |
| 32 | 20260319000001_org_management_rpc.sql | Org management RPCs |
| 33 | 20260319000002_user_management_rpcs.sql | User management RPCs |
| 34 | 20260320000001_invitations.sql | Invitations table |
| 35 | 20260320000002_invitation_rpcs.sql | Invitation RPCs |
| 36 | 20260321000001_contract_approval_workflow.sql | Contract approval workflow |
| 37 | 20260322000001_asset_org_isolation.sql | Asset org isolation |
| 38 | 20260322000002_vehicles_table.sql | Vehicles table |
| 39 | 20260324000001_rule_studio_rpcs.sql | Rule Studio RPCs |
| 40 | 20260325000001_anti_corruption_edge.sql | Anti-corruption edge + idempotency (INV-24) |
| 41 | 20260325000002_asset_status_events.sql | Asset status events (INV-13) |
| 42 | 20260401000001_audit_packages.sql | Audit packages + INV-16 export sealing |
| 43 | 20260401000002_shadow_mode_simulations.sql | Shadow mode simulation table (Phase 10.3) |
| 44 | 20260401000003_monthly_audit_package_rpc.sql | Monthly audit package RPC |
| 45 | 20260402000001_fix_audit_packages_jwt_path.sql | JWT path fix: audit_packages |
| 46 | 20260402000002_contractor_viewer_dual_key.sql | Dual-key isolation (INV-20) |
| 47 | 20260403000001_system_audit_log.sql | System audit log |
| 48 | 20260403000002_rls_dual_key_audit.sql | RLS dual-key on audit |
| 49 | 20260403000003_pii_masking.sql | PII masking functions |
| 50 | 20260403000004_performance_indexes.sql | Performance indexes |
| 51 | 20260404095000_add_spoofing_audit.sql | Spoofing audit (INV-21) |
| 52 | 20260404120000_ledger_v2_immutability_triggers.sql | Ledger immutability triggers (INV-1) |
| 53 | 20260405000001_super_admin_foundation.sql | SuperAdmin foundation |
| 54 | 20260405000002_tenant_billing_events.sql | Tenant billing events |
| 55 | 20260405000003_super_admin_tenant_health_view.sql | Tenant health view |
| 56 | 20260405000004_system_audit_log_org_id.sql | org_id on system_audit_log |
| 57 | 20260405000005_super_admin_rpcs.sql | SuperAdmin RPCs |
| 58 | 20260405000006_super_admin_rls_hardening.sql | SuperAdmin RLS hardening |
| 59 | 20260405000007_super_admin_rpcs_service_role_bypass.sql | Service role bypass for SuperAdmin |
| 60 | 20260406000001_sanction_review_queue.sql | Sanction review queue |
| 61 | 20260406000002_sanction_queue_trigger.sql | Sanction queue trigger |
| 62 | 20260406000003_sanction_escalation_log.sql | Sanction escalation log |
| 63 | 20260406000004_pending_sanctions_rpc.sql | Pending sanctions RPC |
| 64 | 20260407000000_fix_srq_rls_jwt_path.sql | JWT path fix: sanction_review_queue |
| 65 | 20260408000001_unique_cnpj.sql | Unique CNPJ constraint |
| 66 | 20260408000002_fix_queue_rls_role.sql | Queue RLS role fix |
| 67 | 20260408000003_billing_org_name.sql | Billing org_name column |
| 68 | 20260409000001_fix_trigger_and_audit_log.sql | Trigger + audit log fix |
| 69 | 20260410000001_fix_jwt_hook_toplevel_claims.sql | JWT hook top-level claims fix |
| 70 | 20260410000002_fix_rls_role_path.sql | RLS role path fix |
| 71 | 20260411000001_user_roles_enrich_and_fix_auth.sql | User roles enrichment + auth fix |
| 72 | 20260412000001_fix_accept_invitation_rpc.sql | Accept invitation RPC (3-fix consolidated) |

**Freeze point:** `20260412000001_fix_accept_invitation_rpc.sql`

---

## Table Inventory (26 tables)

| Table | RLS | JWT Path | Key Invariant |
|---|---|---|---|
| organizations | ✅ | app_metadata.org_id | INV-6 |
| user_roles | ✅ | app_metadata.org_id | INV-6, INV-20 |
| contractors | ✅ | app_metadata.org_id | INV-20 |
| contracts | ✅ | app_metadata.org_id | INV-6 |
| contract_rule_sets | ✅ | app_metadata.org_id | INV-6 |
| contractual_rules | ✅ | app_metadata.org_id | INV-6, INV-7 |
| sla_templates | ✅ | app_metadata.org_id | INV-6 |
| operational_zones | ✅ | app_metadata.org_id | INV-6, INV-18 |
| contractual_service_executions | ✅ | app_metadata.org_id | INV-5, INV-6 |
| evaluation_traces | ✅ | app_metadata.org_id | INV-23 |
| sla_audit_ledger_v2 | ✅ | app_metadata.org_id | INV-1, INV-2 |
| financial_daily_snapshots | ✅ | app_metadata.org_id | INV-2, INV-6 |
| operational_alerts | ✅ | app_metadata.org_id | INV-6 |
| invitations | ✅ | app_metadata.org_id | INV-6 |
| vehicles | ✅ | app_metadata.org_id | INV-6 |
| canonical_facts | ✅ | app_metadata.org_id | INV-9, INV-24 |
| asset_status_events | ✅ | app_metadata.org_id | INV-13 |
| spoofing_audit_queue | ✅ | app_metadata.org_id | INV-21 |
| audit_packages | ✅ | app_metadata.org_id | INV-16, INV-17 |
| shadow_mode_simulations | ✅ | app_metadata.org_id | Phase 10.3 |
| system_audit_log | ✅ | app_metadata.org_id (superadmin) | INV-22 |
| sanction_review_queue | ✅ | app_metadata.org_id | INV-21 |
| sanction_escalation_log | ✅ | app_metadata.org_id | INV-15 |
| tenant_billing_events | ✅ | superadmin only | INV-6 |
| organizations_tenant_health (view) | ✅ | superadmin only | Phase 9.1 |
| rule_snapshots | ✅ | app_metadata.org_id | INV-7 |

---

## Active Invariants at Freeze Point

| Invariant | Enforcement Mechanism | Migration |
|---|---|---|
| INV-1 — Immutable Ledger | `REVOKE UPDATE/DELETE` + trigger on sla_audit_ledger_v2 | 20260304195300, 20260404120000 |
| INV-2 — Financial Precision | `BIGINT cents` columns on all financial tables | Throughout |
| INV-3 — UTC Everywhere | `TIMESTAMPTZ` columns, `_utc` suffix convention | Throughout |
| INV-6 — Multi-Tenant RLS | `organization_id` on all tables, RLS enabled | 20260305171000 |
| INV-10 — RLS Tenant Claim | `(auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid` | 20260317000001 |
| INV-13 — Asset State Awareness | `asset_status_events` + evaluation gate | 20260325000002 |
| INV-16 — Export Sealing | `package_hash` (SHA-256) on audit_packages | 20260401000001 |
| INV-18 — Engine Activation Gate | `operational_zones` FK required for plan activation | Throughout |
| INV-20 — Dual-Key Isolation | `contractor_id` in JWT + dual-key RLS policies | 20260402000002 |
| INV-21 — Anti-Spoofing | `spoofing_audit_queue` quarantine | 20260404095000 |
| INV-23 — Verdict Explainability | `evaluation_traces` linked to every ledger entry | 20260305194500 |
| INV-24 — Idempotent Ingestion | `UNIQUE(raw_payload_hash)` on canonical_facts | 20260325000001 |

---

## Freeze Policy

From Phase 10.1 onwards:

1. **No new migrations without PO sign-off** — Any new `.sql` file in `supabase/migrations/` on a PR to `main` requires explicit authorization.
2. **Append-only enforcement** — CI blocks `DROP TABLE`, `DROP COLUMN`, `ALTER TABLE ... DROP COLUMN`, `TRUNCATE` in new migration files.
3. **Timestamp convention** — New migrations must use `YYYYMMDD` prefix ≥ `20260413`.
4. **Lead Reviewer [GO] required** — Any migration touching financial tables, RLS policies, or JWT claims requires forensic audit verdict before merge.
