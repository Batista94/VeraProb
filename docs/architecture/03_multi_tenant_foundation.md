# Multi-Tenant Architecture Design

This document specifies the technical architecture for transforming the BusFlow platform into a strict B2B multi-tenant environment. It defines the boundaries across the storage, compute, and presentation layers.

## 1. Tenant Boundary (The `organization_id` Key)
The fundamental isolation primitive is the `organization_id`. It acts as the partition key across the entire platform.

*   **Ledger Model:** Every event persisted in the `sla_audit_ledger` *must* contain an `organization_id` within the event envelope. An event without an organization context is fundamentally invalid.
*   **Projections:** Read models (like `contractual_financial_snapshot` or `active_alerts`) must inherit the `organization_id` from the events that generated them.
*   **Query Services:** All database queries must explicitly scope to the `organization_id`.

## 2. Event Envelope Structure
The Base Event Envelope must be expanded to guarantee tenant provenance. The Engine must reject any event missing this context before evaluation begins.

```json
{
  "event_id": "uuid",
  "organization_id": "uuid",   // <-- REQUIRED ISOLATION KEY (Validated by Engine)
  "occurred_at_utc": "iso8601",
  "event_type": "string",
  "entity_id": "string",       // e.g., trip_id
  "payload": {},
  "metadata": {
    "causation_id": "uuid?",
    "correlation_id": "uuid?"
  }
}
```

## 3. Auth Integration & JWT Claims
We will leverage Supabase Auth. The default Supabase JWT will be enriched with custom claims containing the user's operational context.

When a user logs in, Supabase issues a JWT. This JWT *must* contain:
*   `sub` (user_id)
*   `app_metadata.org_id` -> `organization_id` (Injected via a Supabase Auth Hook or DB Function at login)
*   `app_metadata.role` -> `ADMIN | OPERATOR | AUDITOR`

## 4. RBAC Model & Role Resolution
Roles define *what* a user can do inside their *Organization*.
*   **Tenant Admin:** Can configure SLA rules, add vehicles, and invite users to their specific `organization_id`.
*   **Operator:** Can interact with the OCC, resolve alerts, and view mapping. Cannot alter SLA parameters.
*   **Auditor:** Read-only access to the financial snapshots and investigation timelines.

A robust database schema supports this:
*   `organizations` (id, name, created_at)
*   `users` (id, email, organization_id, role_id) - *Extends auth.users*

## 5. Row-Level Security (RLS) Policies
Data isolation is guaranteed unconditionally at the database layer through Postgres RLS.
Even if a developer makes a mistake in the Flutter code, or if an API key is leaked, the database will refuse to return data belonging to Company B if the JWT belongs to Company A.

**Example RLS Policy for the Ledger:**
```sql
CREATE POLICY "Tenant Isolation: Read" ON sla_audit_ledger
FOR SELECT USING (
  organization_id = (current_setting('request.jwt.claims', true)::json->'app_metadata'->>'org_id')::uuid
);

CREATE POLICY "Tenant Isolation: Insert" ON sla_audit_ledger
FOR INSERT WITH CHECK (
  -- An operator can only insert events stamped with their own org_id
  organization_id = (current_setting('request.jwt.claims', true)::json->'app_metadata'->>'org_id')::uuid
);
```

## 6. Architectural Considerations

### Global Table vs. Partitioned Tables for the Ledger
**Decision:** Keep a single global `sla_audit_ledger` table partitioned by **PostgreSQL Native HASH Partitioning** on `organization_id`.
*   *Why HASH partitioning?* As opposed to `LIST` partitioning (which creates one physical partition per tenant and breaks at high scale), `HASH` partitioning allocates records across a fixed number of partitions (e.g., 64 or 128). This keeps the table count stable and manageable while still providing excellent query pruning performance and insert distribution.

### Tenant-Safe Projection Keys & Query Discipline
*   **Composite Primary Keys:** All projection tables (e.g., `contractual_financial_snapshot`) must use composite primary keys: `(organization_id, entity_id)` or `(organization_id, trip_id)`. This guarantees cross-tenant safety and prevents entity ID collisions if two tenants use the same internal identifiers.
*   **Query Scoping:** All Query Services and Projections must consistently apply `.eq('organization_id', current_org_id)` as the absolute first filter clause in every database operation. This guarantees performant index scability.

### Realtime Subscriptions & Telemetry
**Decision:** Telemetry streams (Supabase Realtime / WebSockets) must be strictly channelized.
*   Currently, the OCC subscribes to a global stream.
*   In the multi-tenant model, the OCC will subscribe to: `realtime:public:telemetry:organization_id=eq.[YOUR_ORG_ID]`.
*   **Crucial:** Supabase enforces RLS on realtime channels. If User A tries to subscribe to Org B's channel, Supabase will silently drop the connection or filter the payloads, guaranteeing data does not cross tenant wires at the WebSocket layer.

## 7. Tenant Lifecycle
1.  **Creation:** System Admin creates an `Organization` record via a secure internal script or SuperAdmin panel.
2.  **First User:** System Admin provisions the first User (Tenant Admin) linked to that `organization_id`.
3.  **Onboarding:** The Tenant Admin logs in and configures SLA `ContractualRules`.
4.  **Scaling:** The Tenant Admin provisions standard `Operators` internally.
