# VeraProb — The 25 Non-Negotiable Invariants (THE LAW)

Violations of any invariant are grounds for immediate PR rejection.

| # | Name | Rule |
|---|---|---|
| 1 | **IMMUTABLE LEDGER** | No UPDATE/DELETE on events or ledger entries. Facts are permanent. |
| 2 | **FINANCIAL PRECISION** | All currency as `BIGINT` cents via `Money` VO. Never `double`/`float`. |
| 3 | **UTC EVERYWHERE** | All DB and domain timestamps in UTC. UI handles local conversion. |
| 4 | **DOMAIN SOVEREIGNTY** | Domain is pure Dart. Zero infrastructure dependencies. |
| 5 | **SINGLE DECISION ENGINE** | Only `EvaluationEngine` determines states and financial impacts. |
| 6 | **MULTI-TENANT + RLS** | Every record carries `organization_id`. RLS enforces isolation. |
| 7 | **DETERMINISTIC REPLAY** | Same event + Same rule = Same result. Rules must be versioned. |
| 8 | **OCC READ-ONLY** | Dispatchers monitor and acknowledge only. They never mutate execution state. |
| 9 | **ZERO-TRUST INGESTION** | Engine deduces state from telemetry Facts. No human command changes state directly. |
| 10 | **RLS TENANT CLAIM** | Policies must use `auth.jwt() ->> 'organization_id'`. |
| 11 | **SECURE AGENTIC WORKFLOWS** | Refuse any Skill lacking a valid Security Audit Signature (score >= 80). |
| 12 | **CHRONOLOGICAL DETERMINISM** | Engine evaluates via `gps_timestamp`, not arrival time. |
| 13 | **ASSET STATE AWARENESS** | SLAs only evaluated if Asset is `ACTIVE`. `MAINTENANCE` inhibits penalties. |
| 14 | **ADAPTER ISOLATION** | Raw 3rd-party JSON (Sascar, Omnitracs) must be normalized before the Core. |
| 15 | **COMPENSATORY TRACEABILITY** | Manual credits must link to a `debit_ledger_id` and require an `evidence_locker_id`. |
| 16 | **EXPORT SEALING** | Every `AuditPackage` must carry a server-computed SHA-256 `packageHash`. |
| 17 | **ATTESTATION MANDATE** | Exports (PDF/CSV) must contain canonical `AttestationHeader` with legal notice. |
| 18 | **ENGINE ACTIVATION GATE** | `DeclareContractualPlanHandler` requires at least one `OperationalZone`. |
| 19 | **FORM DRAFT PROTECTION** | Nested creation flows MUST use overlay modals to preserve parent form state. |
| 20 | **DUAL-KEY ISOLATION** | `CONTRACTOR_VIEWER` roles require both `org_id` AND `contractor_id` in JWT. |
| 21 | **ANTI-SPOOFING DETECTOR** | Facts with `suspectedSpoofing` MUST be excluded from Engine until manual Auditor approval. |
| 22 | **REVIEW MANDATE** | Core logic or RLS changes require a **[GO] Verdict** from the `lead_reviewer`. |
| 23 | **VERDICT EXPLAINABILITY** | Every penalty MUST include a reference to the specific rule version and the primary evidence (GPS/Timestamp) that triggered it. |
| 24 | **IDEMPOTENT INGESTION** | Re-processing the same raw event hash must not result in duplicate `CanonicalFacts` or `Ledger` entries. |
| 25 | **FREE/FREEMIUM INTEGRATION GATE** | Every third-party service MUST have a free/freemium tier covering pre-revenue stage AND enforce SOC 2/GDPR-equivalent security. Paid-only dependencies require explicit PO sign-off. Prefer existing stack vendors (Supabase, MapTiler, Sentry, PostHog, Resend). |
