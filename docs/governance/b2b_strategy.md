# Engineering Council: B2B Strategy & Architectural Review

The Engineering Council has convened to evaluate the 7 strategic architectural gaps identified in the transition from an early prototype to a true B2B Operational Platform.

Our unanimous consensus: **The risk of building an "Engineering Prototype" instead of a usable product is critical.** The current architecture is a powerful evaluation engine (Ferrari), but it lacks the steering wheel (Admin/Configuration) and dashboard (Explainability/Alerting) required for a real organization to drive it.

---

### 1. Multi-Tenancy Model (`organization_id`)
*   **Is it a real risk?** Yes. Critical priority. A B2B system without strict data boundaries is unviable.
*   **The Architect's Verdict:** `organization_id` must become the root partition key across the entire system.
*   **How it works structurally:**
    *   The `sla_audit_ledger` receives an `organization_id` column.
    *   Row-Level Security (RLS) policies enforce that a user's JWT `org_id` claim strictly scopes read/write access.
    *   Projections (like `contractual_financial_snapshot`) and queries are automatically isolated by the database engine.

### 2. Contract Configuration (Determinism vs. Rules)
*   **Is it a real risk?** Yes. Critical priority.
*   **The Senior Engineer's Verdict:** The engine must be deterministic, but the *rules* it evaluates must be injected at runtime.
*   **How it works structurally:**
    *   We introduce a `ContractualRule` entity (versioned JSON state in the database).
    *   When the Evaluation Engine runs, it requests: *"Give me the active Contract Rules for `organization_id` X at time `occurred_at_utc`."*
    *   Because the rules are versioned by time, **event replay remains 100% deterministic**.
    *   A UI module allows Client Admins to alter these JSON thresholds without developer intervention.

### 3. Decision Explainability
*   **Is it a real risk?** Yes. High priority. 
*   **The QA/Security Verdict:** The engine must attach a `reasoning_payload` to the `execution_states` and financial snapshots.
*   **How it works structurally:**
    *   The projection saves: `{"status": "PENALTY_APPLIED", "trace": {"rule": "Max Lateness (10m)", "actual": "15m", "fine_cents": 5000}}`.

### 4. Operational Alerting
*   **Is it a real risk?** Yes. Medium priority (must follow Explainability).
*   **How it works structurally:**
    *   Alerts are treated as **Derived Projections**. Engine emits `AlertTriggeredEvent`.
    *   Updates `active_alerts` read-model projection table.

### 5. Operational Investigation
*   **Is it a real risk?** Yes. High priority.
*   **The UX / Ops Verdict:** OCC must evolve from a "Monitoring Map" to an "Investigation Interface".
*   **How it works structurally:**
    *   "Timeline Investigation Modal" pulling history from `sla_audit_ledger` with Decision Explainability traces.

### 6. Reporting and Exports
*   **Is it a real risk?** Yes. Medium priority.
*   **How it works structurally:**
    *   Use Supabase Postgres scheduled jobs (`pg_cron`) to aggregate data into `monthly_compliance_reports`.

### 7. The Fundamental Product Risk
*   **Conclusion:** We must halt feature expansion until we build the "B2B Onboarding & Configuration Foundations".

---

## The Correct Evolution Path
1.  **Foundation (Multi-Tenancy & Auth):** `organization_id`, Auth, RBAC, and RLS.
2.  **Configuration (Contracts & Rules):** Versioned rule engines and the Admin UI.
3.  **Trust (Explainability & Investigation):** Reasoning Traces and Timeline UI.
4.  **Proactivity (Alerting & Reports):** Realtime alerts and batch exports.
