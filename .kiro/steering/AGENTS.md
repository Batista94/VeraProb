# VeraProb - KIRO MASTER
SLA/Finance Protection.

## PROTOCOLS
1. TDD: Mandatory. Fail test BEFORE code.
2. DESIGN: Industrial Dark. Micro-anim, glassmorphism, 8pt, Inter/Outfit. "Forensic/Precise".
3. ORCHESTRATION: Proactive Council. UX/Ops for arch/UI. QA/Senior sign-off.
4. RESPONSE: Brief "Forensic Insight" + INV-X. UI: Direct fix.

## FORENSIC INVARIANTS (INV-1 to INV-27)
Full: .claude/rules/forensic-standards.md

| ID | Rule |
|----|------|
| 1 | org_id filter ALL. Fail-Fast JWT. |
| 2 | RLS: auth.jwt() organization_id. NO uid. |
| 3 | Ledger: APPEND-ONLY. NO Update/Delete. |
| 4 | Money: BIGINT cents (DB/DTO). Money VO (Domain). |
| 5 | Round: (cents * bps + 5000) ~/ 10000. |
| 6 | UTC: DateTime.now().toUtc() ONE LINE. |
| 7 | Type: No dynamic. Strict null safety. |
| 8 | Repo: Enforce org_id. |
| 9 | Seal: SHA-256 telemetry/files. |
| 10| Error: IntegrityException. No silent fail. |
| 11| Skill: State context before logic change. |
| 12| Double: Annotate // Physical Metric. |
| 13| Layers: C4. Features NO Domain/Infra import. |
| 14| Transp: Use Asset/Operator/Execution contexts. |
| 15| Deter: Byte-identical replay. |
| 16| Limits: Max 60 DB connections. Pool/Stream. |
| 17| Web: dart:js_interop (WASM). |
| 18| Trust: Telemetry untrusted until normalized. |
| 19| JIT: Inline master data in flows. |
| 20| Time: DateTimeRange + UTC normal. |
| 21| Audit: Engine verdict -> Snapshot ID. |
| 22| Isol: Tenant isolation (Red Team target). |
| 23| Budget: Free tier for pre-revenue. |
| 24| Sec: Agentic need Security Audit Signature. |
| 25| Stack: Supabase, MapTiler, PostHog, Resend, Sentry. |
| 26| Parity: 404 for Not Found/Wrong Org. |
| 27| Origin: Verify source ownership. |

---
## PERSONAS
Council: Architect, Senior, QA/Sec, UX/Ops, Maverick.
Refer human-readable backup if needed: CLAUDE.original.md
