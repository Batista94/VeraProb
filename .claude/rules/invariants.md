# VeraProb: The 25 Non-Negotiable Invariants (THE LAW)

> [!IMPORTANT]
> This file is a mirror of the **Official Forensic Manifesto** located at `/docs/governance/forensic_manifesto.md`. 
> It exists here to ensure Claude (the assistant) has immediate access to these rules.
> Violations of any invariant are grounds for immediate PR rejection.

---

| # | Name | Rule Summary | Reference |
|---|---|---|---|
| 1 | **TENANT ISOLATION** | Every query MUST filter by `organization_id`. | INV-1 |
| 2 | **DUAL-KEY ACCESS** | Contractor access requires `org_id` + `contract_id`. | INV-2 |
| 3 | **ENV ISOLATION** | No secrets in code. Use `EnvironmentConfig`. | INV-3 |
| 4 | **WASM-READY** | Zero use of `dart:html`/`js`. Use `interop`. | INV-4 |
| 5 | **RLS AUTHORITY** | Policies must use canonical JWT claims. | INV-5 |
| 6 | **SUPERADMIN LOCK** | Access requires MFA and `super_admin=true`. | INV-6 |
| 7 | **IMMUTABLE LEDGER** | No `UPDATE`/`DELETE` on ledger entries. | INV-7 |
| 8 | **EVIDENCE HASHING** | Photos/Logs must have SHA-256 server hashes. | INV-8 |
| 9 | **UTC EVERYWHERE** | All timestamps in UTC. No exceptions. | INV-9 |
| 10 | **CHRONO DETERMINISM** | Evaluate via `gps_timestamp`, not arrival. | INV-10 |
| 11 | **IDEMPOTENCY** | Repeat events must not duplicate facts. | INV-11 |
| 12 | **LATE-ARRIVAL** | 48h window for re-processing protocol. | INV-12 |
| 13 | **BINARY VERDICTS** | SLA must result in Guilty or Innocent. | INV-13 |
| 14 | **SERVER AUTHORITY** | Verdicts calculated on Edge, never Client. | INV-14 |
| 15 | **STATE INHIBITION** | `MAINTENANCE` status inhibits penalties. | INV-15 |
| 16 | **ZERO-TRUST** | Engine deduces state from Facts only. | INV-16 |
| 17 | **KINEMATIC GUARD** | Database-level validation of $v = \Delta d / \Delta t$. | INV-17 |
| 18 | **DOMAIN SOVEREIGNTY**| Core Domain is pure Dart (no Supabase infra). | INV-18 |
| 19 | **PENNY PRECISION** | All currency as `BIGINT` cents via `Money`. | INV-19 |
| 20 | **PACKAGE SEALING** | Exports carry server-computed `packageHash`. | INV-20 |
| 21 | **ATTESTATION** | Exports require legal `AttestationHeader`. | INV-21 |
| 22 | **TRACEABILITY** | Manual credits must link to a debit entry ID. | INV-22 |
| 23 | **OCC READ-ONLY** | Cockpit monitors but does not mutate state. | INV-23 |
| 24 | **DRAFT PROTECTION** | Overlay modals for nested creation flows. | INV-24 |
| 25 | **ACTIVATION GATE** | Plan requires at least one `OperationalZone`. | INV-25 |

---

> [!TIP]
> **Full manifesto with detailed explanations:** [Forensic Manifesto](file:///c:/Projects/VeraProb/docs/governance/forensic_manifesto.md)
