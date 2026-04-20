# VeraProb - MASTER ORCHESTRATOR

Automated SLA Compliance & Financial Protection Platform.

## CORE PROTOCOLS

1. TEST-DRIVEN DEVELOPMENT (TDD): Mandatory for all logic. Write a failing test for the requirement (using IntegrityException if applicable) BEFORE implementing code.
2. PREMIUM DESIGN AESTHETIC: All UI must be "State of the Art":
   - Theme: Industrial High-End Dark Mode (Industrial Deep palette).
   - Details: Rich micro-animations, glassmorphism, 8pt spatial system, and bold modern typography (Inter/Outfit).
   - Vibe: "Forensic, Precise, Unrivaled." NO generic white/purple AI aesthetics.
3. COUNCIL ORCHESTRATION:
   - Systemic Thinking: For any non-trivial task, orchestrate relevant personas from .claude/agents/.
   - Integrity Guard: Architectural changes MUST involve UX/Ops if they impact how evidence is displayed or high-stakes decisions are made.
   - Cross-Functional Alignment: Ensure the Senior Engineer and QA sign off on core logic.
4. DYNAMIC RESPONSE:
   - Structural/Logic Changes: Provide a brief "Forensic Insight" referencing relevant INV-X.
   - UI/Trivial Fixes: Direct implementation. No boilerplate needed.

## THE 27 FORENSIC INVARIANTS (INV-1 to INV-27)

Full details in .claude/rules/forensic-standards.md. Summary for active context:

| ID | Category | Rule |
|----|----------|------|
| INV-1 | Identity | Filter ALL queries/flows by organization_id. Fail-Fast on JWT mismatch. |
| INV-2 | RLS | Policies must use auth.jwt() ->> 'organization_id'. NO auth.uid(). |
| INV-3 | Ledger | Verdict/Financial tables are APPEND-ONLY. NO Update/Delete. |
| INV-4 | Money | BIGINT (cents) in DB; int cents in DTOs; Money Value Object in Domain. |
| INV-5 | Precision | Symmetric Rounding: (cents * bps + 5000) ~/ 10000. No truncation. |
| INV-6 | UTC | DateTime.now().toUtc() on ONE LINE. Mandatory across all layers. |
| INV-7 | Type | No dynamic. Strict null safety. |
| INV-8 | Repo | Repositories MUST enforce org_id on all operations. |
| INV-9 | Sealing | SHA-256 hashing at ingestion for all raw telemetry/files. |
| INV-10 | Error | Use IntegrityException for domain violations. No silent failures. |
| INV-11 | Insight | State Skill/Invariant context before structural logic changes. |
| INV-12 | Doubles | Annotate non-currency doubles with // Physical Metric - Double Required. |
| INV-13 | Layers | C4: Features must NOT import Domain or Infrastructure. |
| INV-14 | Transport | Transport-agnostic Core: Use Asset/Operator/Execution contexts. |
| INV-15 | Deter. | Evaluation yields byte-identical results on replay. |
| INV-16 | Limits | Max 60 concurrent DB connections. Design for pooling/streaming. |
| INV-17 | Web | Use dart:js_interop for WASM compatibility. |
| INV-18 | Trust | All telemetry is untrusted facts until normalized. |
| INV-19 | JIT | Inline creation of master data (Assets/Zones) in contract flows. |
| INV-20 | Time | Use DateTimeRange + UTC normalization for all schedules. |
| INV-21 | Audit | Every Engine verdict must carry a traceable Snapshot ID. |
| INV-22 | Isolation | Tenant-A must NEVER see Tenant-B's data (Violations = Red Team Fail). |
| INV-23 | Budget | 3rd-party services must have a free tier for pre-revenue stage. |
| INV-24 | Security | Agentic instructions require a Security Audit Signature. |
| INV-25 | Stack | Supabase, MapTiler, PostHog, Resend, Sentry. SOC 2 compliant. |
| INV-26 | Parity | 404 for "Not Found" AND "Other Org" (prevents Oracle Attacks). |
| INV-27 | Origin | Source-to-dest transfers MUST verify source ownership. |

---

## COMMANDS & PERSONAS

- /audit -> bash scripts/pr_full_scanner.sh + forensic check.
- /tdd -> Start a Test-Driven Development flow.
- /init -> Sync all rules.
- Council: Architect, Senior Engineer, QA & Security, UX/Ops, Business Maverick.
