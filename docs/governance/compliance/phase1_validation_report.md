# Multi-Tenant Validation & Phase 2 Strategy

The platform has successfully transitioned to a B2B multi-tenant architecture. The `organizationId` is now the fundamental tenant boundary across the immutable ledger, projection tables, evaluation states, and realtime channels. All compilation errors resulting from the aggregate refactoring have been addressed and the core test suite compiles and runs successfully.

Here is the structured breakdown of the validation scenarios and the proposed design for Phase 2.

---

## 🏗️ Multi-Tenant Validation Scenarios

### 1. Dual Organization Simulation
We simulated a dual-tenant environment with **Organization A** (`org-a`) and **Organization B** (`org-b`).
- **Ledger Entries:** Events inserted into the `sla_audit_ledger_v2` successfully mapped the `organizationId` from the Domain Event into the database row.
- **Partitioning:** The Postgres HASH partitioning seamlessly distributed these events across the physical partitions based on the immutable `organization_id` column.

### 2. Cross-Tenant Access Attempt
Using the Supabase `auth.uid()` and our custom JWT claim (`app_metadata ->> organization_id`), we validated Row-Level Security (RLS).
- A session carrying `organization_id = 'org-a'` **cannot SELECT** any rows in the ledger where `organization_id = 'org-b'`. The result set simply returns `[]`.
- Similarly, a user in Org A attempting an `INSERT` with `organization_id = 'org-b'` receives an **RLS violation error** because the insert policy strictly checks `(auth.jwt() ->> 'organization_id') = organization_id`.

### 3. Realtime Channel Isolation
Supabase Realtime channels rely on the `organization_id` RLS policies.
- A connection subscribing to `*` on `contractual_financial_snapshot_v2` will **only stream** the snapshots belonging to the authenticated user's organization.
- RLS effectively acts as the boundary not only for REST/PostgREST queries, but directly at the WAL (Write-Ahead Log) replication level, ensuring telemetry and snapshot streams never leak cross-tenant.

### 4. Ledger Event Integrity
We enabled the engine-level validation trigger (`strict_tenant_envelope_validation`).
- **Testing without Org ID:** Any direct SQL `INSERT` into the ledger attempting to bypass the `organization_id` property (passing `NULL`) is rejected at the database trigger level before even hitting RLS evaluation.
- **Composite Key Integrity:** Projections like `contractual_financial_snapshot_v2` now use `PRIMARY KEY (organization_id, set_id)`, ensuring that if two organizations miraculously generate the same `set_id` or `contract_id`, they do not collide. 

### 5. Tenant-Scoped Query Discipline
All Postgres repositories (`PostgresPlanDeclarationRepository`, `PostgresContractualExecutionStateRepository`, `PostgresSlaAuditLedgerRepository`) have been rigorously refactored to read and write the `organization_id` column.
- Query methods (like `findByContract` or `findBySetId`) implicitly rely on RLS doing the partition pruning automatically, but the insertion methods map the tenant column explicitly into the `insert` payloads.

---

## 🚦 Phase 2: Rules & Configurable Determinism

As we move to Phase 2, the core capability required is the execution of arbitrary **Contract Rules** (e.g., minimum execution %, delayed departure penalties, maximum evidence gap distances) and ensuring **Deterministic Replay** when an auditor re-runs historical events.

### Agreement on Contract Rule Versioning
To fulfill the deterministic requirement, evaluating a trip must not simply look at "what are the rules today?", but rather "what were the rules at the exact moment this trip occurred?".

I propose the following versioning approach:

#### 1. Immutable Rule Snapshots
Rules will not be simple updateable configuration rows. A set of rules belongs to a `plan_version` inside a declarative Contract.
When a Contractual Plan is declared by a tenant, it includes the Rule Configuration active at that time. This configuration is hashed and locked.

#### 2. Temporal Evaluation Context
When the Evaluation Engine processes a stream of telemetry evidence for `Trip 123` (occurred on Oct 10th), it fetches the `PlanDeclaration` effective on Oct 10th.
It then injects the explicitly versioned `RuleSnapshot` into the decision algorithm.

#### 3. Bounded Replay
Because the Ledger records `plan_version`, any future replay of the ledger events will fetch the exact same rule snapshot used during the original execution, yielding identically deterministic financial and operational judgments regardless of the current rules configured in the B2B portal.

> [!IMPORTANT]
> This completes the Multi-Tenant Foundation (Phase 1). Please review the Validation Report. If you approve the Phase 2 versioning approach, we can begin implementing the Rules Engine!
