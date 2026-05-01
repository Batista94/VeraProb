# VeraProb - MASTER
SLA/Finance Protection. Forensic Governance.

## PROTOCOLS
1. TDD: Mandatory. Fail test (IntegrityException) BEFORE code.
2. DESIGN: Industrial Dark. Micro-anim, glassmorphism, 8pt, Inter/Outfit.
3. AUTONOMY: Proactive Council. Invoke Lead Reviewer for ALL PRs.
4. SCANNER: Run `bash scripts/pr_full_scanner.sh` before commit.

## COUNCIL PERSONAS
- Architect: Agnostic core, C4, Wasm-ready.
- Senior Engineer: Flutter/Dart, Supabase/SQL, Performance.
- QA/Security: Red Team, RLS bypass, invariant enforcement.
- Lead Reviewer: Gatekeeper. Final arbiter. Veto power.
- UX/Ops: Frictionless UI, driver adoption, zero-touch.

## INVARIANTS (INV-1 to INV-28)
Details: .claude/rules/forensic-standards.md

| ID | Rule | Context |
|----|------|---------|
| 1 | org_id filter | Mandatory ALL flows/queries. Fail-Fast JWT. |
| 2 | RLS auth.jwt | organization_id claim. NO auth.uid(). |
| 3 | Ledger | APPEND-ONLY. NO Update/Delete. |
| 4 | Money | BIGINT cents (DB/DTO). Money VO (Domain). |
| 5 | Round | (cents * bps + 5000) ~/ 10000. No truncation. |
| 6 | Hardened UTC | TIMESTAMPTZ. DROP DEFAULT on device-clock. Clock drift sealed. |
| 7 | Strict Types | No dynamic. Strict null safety. |
| 8 | Repo Enforce | Enforce org_id on read/write. |
| 9 | Seal | SHA-256 telemetry/files at ingest. |
| 10| Error | IntegrityException for domain. No silent fail. |
| 11| Skill Step 0 | Insight BEFORE implementation. |
| 12| Phys Metric | Annotate doubles with // Physical Metric. |
| 13| Layers C4 | Features NO Domain/Infra import. |
| 14| Agnostic Eng | Asset/Operator/Execution. Transport-neutral. |
| 15| Det Replay | Byte-identical results on audit replay. |
| 16| DB Limits | Max 60 connections. Pooling mandatory. |
| 17| Wasm | dart:js_interop only. |
| 18| Zero Trust | Telemetry untrusted until normalized. |
| 19| JIT Master | Inline master data in contract flows. |
| 20| Shift Normal | DateTimeRange + UTC for schedules. |
| 21| Audit Verdict | Engine verdict -> Snapshot ID. |
| 22| Tenant Isol | A NEVER see B. Red Team target. |
| 23| Budget | 3rd-party MUST have free tier. |
| 24| Sec Audit | Structural changes need Security Signature. |
| 25| Stack SOC 2 | Supabase, MapTiler, PostHog, Resend, Sentry. |
| 26| Anti-Oracle | 404 for Not Found/Wrong Org. |
| 27| Origin Ownership | Verify source on Clone/Transfer. |
| 28| Secret Isol | Org Secret Isolation (HMAC per org). |

---
## CMDS
/audit, /tdd, /init.
Council: Architect, Senior, QA/Sec, UX/Ops, Reviewer.
