# Phase 2 Design Specification: Contract Rules & Configurable Determinism

## 1. Goal Description
The objective of Phase 2 is to replace hardcoded SLA rules with a polymorphic, configurable rule system that allows organizations to define their own contractual parameters.

Per Engineering Council constraints, the architecture must guarantee **Deterministic Replay Safety**. This is achieved by ensuring that rule configurations (stored as JSON) only define **parameters**, not executable logic. The `ContractualEvaluationEngine` remains the sole interpreter of these parameters, executing deterministic Dart algorithms based on a fixed rule taxonomy.

## 2. Rule Architecture Principles
- **Parameter-Only Configurations:** The database stores rule structures as pure data parameters (e.g., `{"threshold_minutes": 10}`). No DSL or executable code is stored.
- **Engine as Interpreter:** The engine maps a declarative `rule_type` to a specific deterministic algorithm implemented in the platform's core code.
- **Snapshot Immutability:** Rules are temporally bound to a plan version upon declaration. Historic replay perfectly reproduces past evaluations using the exact parameter snapshots active at the time.

## 3. Rule Type Taxonomy
A fixed taxonomy of supported evaluation algorithms implemented in the engine. Example taxonomy:
- `MAX_TOLERANCE_DELAY`: Limits how late a trip can start before a penalty or violation is triggered. Parameters: `{"threshold_minutes": 15}`.
- `MAX_EVIDENCE_GAP`: Limits the maximum distance/time between telemetry points before an evidence gap is declared. Parameters: `{"max_distance_meters": 500}`.
- `MIN_GEOFENCE_COVERAGE`: Minimum geofence adherence required to consider the trip successfully executed. Parameters: `{"min_coverage_pct": 95}`.
- `NO_SHOW_PENALTY`: Financial penalty multiplier for no-shows. Parameters: `{"multiplier_value": 1.5}`.

## 4. Rule Parameter Storage & Versioning Structure
To provide clear operational auditability, rules are not simply overwritten. Instead, they are organized into discrete rule sets and their historical changes are tracked.

**Table `contract_rule_sets`:** Logically groups rules for a specific contract.
- `id` (UUID)
- `contract_id` (String)
- `organization_id` (UUID, Tenant Isolation)

**Table `contract_rule_versions`:** Tracks the historical configuration of rules within a set.
- `id` (UUID, primary key acting as `rule_id`)
- `rule_set_id` (UUID, foreign key to `contract_rule_sets`)
- `rule_type` (Enum matching taxonomy, enforced by Postgres TYPE)
- `rule_config` (JSONB, validated by Postgres check constraints for required parameters)
- `rule_version` (Integer, auto-incrementing per set/type)
- `evaluation_order` (Integer, determines the deterministic sequence in which rules are applied)
- `active_from_utc` (Timestamp)
- `active_to_utc` (Timestamp, null if currently active)

**Database Safeguards:**
- **Uniqueness:** A partial unique index ensures a `rule_set_id` cannot have more than one active `rule_type` simultaneously (`WHERE active_to_utc IS NULL`).
- **Indexing:** B-tree indices on `(contract_id, active_to_utc)` and `(rule_set_id, rule_type)` ensure efficient snapshot generation.
- **Taxonomy Enforcement:** `rule_type` must be an explicit Postgres Enum, guaranteeing deterministic mappings.
- **Config Validation:** Check constraints (or trigger validations) ensure that `rule_config` contains the exact expected JSON keys for the specified `rule_type`.

This structure ensures that the current active configuration can be requested easily, but full historical evolution is preserved independently of executions.

## 5. Temporal Rule Snapshotting (Deterministic Replay)
To ensure replays are fundamentally safe and decoupled from the active configurations, rules must be snapshotted temporally.

**The Snapshot Algorithm:**
1. When a new `PlanDeclaration` is created, the system queries the active `contract_rule_versions` (where `active_to_utc` is null) for the given `contract_id`.
2. These precise rule versions are compiled into a `RuleSnapshot` object. This snapshot includes the `rule_id`, `rule_type`, `rule_version`, `evaluation_order`, and `rule_config`.
3. The snapshot is serialized into JSON and stored immutably inside the `plan_declarations` table within the `rule_snapshot_jsonb` column.
4. The snapshot data is cryptographically hashed as a forensic seal against tampering.

## 6. Engine Resolution & Deterministic Execution
When the `ContractualEvaluationEngine` is evaluating `ContractualExecutionState`, it follows these strict, deterministic steps:
1. It inspects the `plan_version` of the state being evaluated.
2. It fetches the `PlanDeclaration` corresponding to `(contract_id, plan_version)`.
3. It extracts the `RuleSnapshot` embedded in the declaration.
4. **Ordering:** The engine sorts the rules in the snapshot ascending by `evaluation_order`.
5. **Execution:** Iterating through the sorted list, the engine maps the `rule_type` to its corresponding Dart evaluator.
6. The engine passes the `rule_config` parameters into the evaluator.
7. **Explainability Tracking:** When an evaluator produces an outcome (e.g., assessing a penalty), the engine records the `rule_id`, `rule_type`, and `rule_version` in the resulting financial snapshot or event payload, creating a stable, traceable decision (e.g., "Penalty applied by MAX_TOLERANCE_DELAY (rule_version 3)").

## Proposed Changes

### Domain Layer
#### [NEW] `lib/domain/sla_audit/contractual_rule.dart`
Value object representing a rule configuration (type and parameters).
#### [NEW] `lib/domain/sla_audit/rule_snapshot.dart`
Value object representing the frozen state of rules embedded within a plan.
#### [MODIFY] `lib/domain/sla_audit/plan_declaration.dart`
Extend the aggregate to accept and store a `RuleSnapshot` upon creation.

### Application Layer
#### [MODIFY] `lib/application/sla_audit/contractual_evaluation_engine.dart`
Update the evaluation algorithms to dynamically fetch parameters from the `PlanDeclaration`'s rule snapshot, instead of hardcoding business thresholds.
#### [MODIFY] `lib/application/sla_audit/declare_contractual_plan_handler.dart`
Update the handler to fetch active configurations from the new `ContractualRuleRepository` and inject them as a snapshot when creating the `PlanDeclaration`.

### Infrastructure Layer (Postgres)
#### [NEW] `supabase/migrations/XXX_contract_rules.sql`
Create the `contract_rule_sets` and `contract_rule_versions` tables (with RLS policies and `organization_id`) and add the `rule_snapshot_jsonb` column to the `plan_declarations` table.
#### [NEW] `lib/domain/sla_audit/contractual_rule_repository.dart`
Interface for managing the rule sets and retrieving active rule versions.
#### [NEW] `lib/infrastructure/sla_audit/postgres_contractual_rule_repository.dart`
Postgres implementation with tenant-isolation queries.
#### [MODIFY] `lib/infrastructure/sla_audit/postgres_plan_declaration_repository.dart`
Update persistence and reconstitution to handle the `rule_snapshot_jsonb` column.

## Verification Plan
1. **Time-Travel Test:** Create Plan v1 with 10-minute delay tolerance. Process a trip at 12 mins delay (triggers violation). Create Plan v2 with 15-minute tolerance. Replay the same trip against the ledger; verify it still correctly triggers a violation securely linked to the embedded snapshot's parameters.
2. **Tenant Isolation:** Configure Org A with unique parameters and Org B with different parameters. Verify their respective engines do not cross-pollinate configurations.
3. **Database Integrity:** Execute an insert representing a new rule version into `contract_rule_versions` and verify that already-declared plans structurally retain their historical parameters.
4. **Explainability Completeness:** Verify generated outputs (evidence, logs) contain `rule_id` and `rule_version` indicating the exact parameter origin.
