# VeraProb - FORENSIC STANDARDS
Source of Truth. Council Orchestration & Token Efficiency.

## ⚖️ THE 27 INVARIANTS (INV-1 to INV-27)
Details: .claude/rules/forensic-standards.original.md

| ID | Rule |
|----|------|
| 1 | org_id filter ALL flows/queries. Validate JWT claim (Fail-Fast). |
| 2 | RLS: auth.jwt() organization_id. NO auth.uid(). Views MUST use `WITH (security_invoker = true)`. Partitions MUST each have their own `ENABLE ROW LEVEL SECURITY` + mirrored policy (CI blocks #11, #12). |
| 3 | Ledger: APPEND-ONLY. NO UPDATE/DELETE. |
| 4 | Money: BIGINT cents (DB); int (DTO); Money VO (Domain). |
| 5 | Round: (cents * bps + 5000) ~/ 10000. No raw truncation. |
| 6 | UTC: TIMESTAMPTZ mandatory DB-wide. PROHIBIT timestamp without time zone. IDateTimeProvider.nowUtc() ALL layers. Device-clock columns MUST DROP DEFAULT (prevent server-clock substitution). clock_drift sealed at ingest (INV-15). |
| 7 | Type: No dynamic. Strict types only. |
| 8 | Repo: Enforce org_id on ALL read/write. |
| 9 | Seal: SHA-256 ingestion for all raw telemetry/files. |
| 10| Error: IntegrityException for domain violations. No silent fail. |
| 11| Skill: Step 0 Skill Insight BEFORE implementation. |
| 12| Scan: Annotate doubles with // Physical Metric - Double Required. |
| 13| Layer: C4. Features NO Domain/Infra import. |
| 14| Eng: Transport-agnostic Core: Asset/Operator/Execution. |
| 15| Det: Byte-identical replay results. |
| 16| Conn: Max 60 DB connections (Free Tier). Use pooling. |
| 17| Wasm: dart:js_interop ONLY. No legacy js/html. |
| 18| Trust: Zero-Trust telemetry until normalized. Quarantine spoofs. |
| 19| JIT: Inline master data (Zones/Assets) in contract flows. |
| 20| Shift: DateTimeRange + UTC normal for schedules. |
| 21| Audit: Engine verdict -> Snapshot ID. |
| 22| Isol: Tenant-A NEVER see Tenant-B. Red Team tested. |
| 23| Budget: 3rd-party MUST have free tier. |
| 24| Sec: Mandatory Security Audit Signature for instructions. |
| 25| Stack: Supabase, MapTiler, Sentry, PostHog, Resend. SOC 2. |
| 26| Parity: 404 for Not Found AND Wrong Org (Anti-Oracle). |
| 27 | Origin: Verify source ownership on Clone/Transfer. |
| 28 | Secret: Org Secret Isolation (HMAC per org). |

## 🔄 EXECUTION PROTOCOLS
1. **Step 0:** State Skill Insight + Relevant INV-X.
2. **TDD:** Fail test (IntegrityException) -> Pass -> Refactor.
3. **Scanner:** Run `bash scripts/pr_full_scanner.sh` before PR.
4. **Consensus:** Architect + Senior + QA sign-off for structural change.

## 🛠️ TECH STANDARDS
- **Flutter:** Riverpod (Generator). AsyncValue UI. Industrial Deep palette. WASM/CanvasKit.
- **Supabase:** Idempotent SQL migrations. RLS enabled ALL tables. Explicit Data API grants required for all new tables. 200 OK for duplicate telemetry.
- **AI/Agentic:** `prompt-injection-auditor` for summaries. Cryptographic workflow sealing.

## 🚄 PERF & BUDGET
- Models: Sonnet (Dev) | Opus (Arch/Review).
- Memory: Prune history. Roadmap -> ROADMAP_HISTORY.md.
- Tokens: Tables > Bullets > Paragraphs.
