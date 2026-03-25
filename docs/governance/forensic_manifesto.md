# VeraProb: Forensic Audit Manifesto & Core Invariants

> [!IMPORTANT]
> This is the **Single Source of Truth (SSOT)** for all forensic, security, and architectural invariants of the VeraProb platform.
> Any code change violating these rules must be rejected ([NO-GO]).

---

## I. Infrastructure & Security (Tenant Isolation)

1.  **[INV-1] Tenant Isolation**: Every database query and application flow MUST filter by `organization_id`.
2.  **[INV-2] Dual-Key Access**: Contractor/Viewer access MUST require both `org_id` and `contract_id` verification.
3.  **[INV-3] Environment Isolation**: Zero secrets in code. Use `EnvironmentConfig` for runtime injection of keys.
4.  **[INV-4] Wasm-Ready**: Zero use of `dart:html` or `dart:js`. Use `dart:js_interop` and `package:web`.
5.  **[INV-5] RLS Authority**: Row-Level Security policies MUST use canonical JWT claims (`auth.jwt() ->> 'organization_id'`).
6.  **[INV-6] SuperAdmin Lock**: SuperAdmin access requires a dedicated `super_admin=true` claim and MFA.

## II. Data Integrity & Evidence (The Ledger)

7.  **[INV-7] Immutable Ledger**: No `UPDATE` or `DELETE` on events or ledger entries. Facts are permanent; only compensating records are allowed.
8.  **[INV-8] Evidence Hashing**: Every evidence file (photo/log) must have a server-side computes SHA-256 hash stored in the record.
9.  **[INV-9] UTC Determinism**: All timestamps MUST be stored and processed in UTC. UI handles local conversion.
10. **[INV-10] Chronological Determinism**: The engine evaluates based on `gps_timestamp`, not arrival time or database sequence.
11. **[INV-11] Idempotent Ingest**: Processing the same raw event hash multiple times MUST NOT result in duplicate facts or ledger entries.
12. **[INV-12] Late-Arrival Window**: Events arriving after the processing window (e.g., 48h) must follow the re-evaluation protocol without breaking INV-10.

## III. Evaluation Engine Logic (The Judge)

13. **[INV-13] Binary Verdicts**: SLA rules must yield deterministic "Guilty" or "Innocent" statuses. No ambiguous states.
14. **[INV-14] Server-Side Authority**: Final contractual verdicts are calculated on Supabase Edge/Database, never on the Client.
15. **[INV-15] Asset State Inhibition**: SLA penalties are inhibited if the Asset (Vehicle) status is `MAINTENANCE` during the event window.
16. **[INV-16] Zero-Trust Deducation**: The engine deduces state from telemetry Facts. No human command can force a "success" state without evidence.
17. **[INV-17] Kinematic Guard**: Telemetry validation ($v = \Delta d / \Delta t$) must prevent Fake GPS injection at the database level.
18. **[INV-18] Domain Sovereignty**: The Core Domain layer must remain pure Dart, with zero dependencies on infrastructure (Supabase/Flutter).

## IV. Financial & Legal Compliance (Precision)

19. **[INV-19] Penny Precision**: All currency and financial values MUST be handled as `BIGINT` cents via the `Money` Value Object. No `double`.
20. **[INV-20] Package Sealing**: Exported audit packages (PDF/CSV) must carry a server-computed `packageHash`.
21. **[INV-21] Attestation Header**: All exports must contain the canonical legal notice and CNPJ validation.
22. **[INV-22] Compensatory Traceability**: Manual credits MUST link to a specific `debit_ledger_id` and require a valid `evidence_locker_id`.

## V. UX & Operational Excellence

23. **[INV-23] OCC Read-Only**: The Operations Center (Cockpit) monitors and acknowledges state but never mutates internal engine state directly.
24. **[INV-24] Form Draft Protection**: Nested creation flows MUST use overlay modals to prevent data loss in the parent form.
25. **[INV-25] Activation Gate**: Plan declarations require at least one valid `OperationalZone` defined for the organization.

---

> [!TIP]
> **Enforcement**: These rules are automatically verified by the `scripts/pr_scanner.sh` and enforced by the `lead-reviewer` agent.
