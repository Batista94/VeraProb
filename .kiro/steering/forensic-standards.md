# VeraProb — FORENSIC STANDARDS & ORCHESTRATION

This document is the **Single Source of Truth** for the VeraProb Council. It consolidates all invariants, protocols, and technical standards to ensure maximum instruction density and token efficiency.

---

## ⚖️ THE 27 FORENSIC INVARIANTS (INV-1 to INV-27)

| ID | Category | Rule |
|----|----------|------|
| INV-1 | Identity Sovereignty | Every database query and application flow MUST filter by `organization_id`. The application layer MUST validate that the `organization_id` matches the JWT claim before processing (Fail-Fast). |
| INV-2 | RLS Hardening | Policies must use `auth.jwt() ->> 'organization_id'`. NO `auth.uid()`. |
| INV-3 | Ledger Integrity | Financial/Verdict tables are APPEND-ONLY. NO `UPDATE` or `DELETE`. |
| INV-4 | Money Type | Use `BIGINT` (cents) for DB; `int` for DTOs; `Money` VO for Domain. |
| INV-5 | BPS Precision | Symmetric Rounding: (cents * bps + 5000) ~/ 10000. Forbid raw truncation. |
| INV-6 | UTC Mandatory | `DateTime.now().toUtc()` on ONE LINE. Regex-enforced. |
| INV-7 | Null Safety | No `dynamic` in application code. Strict types only. |
| INV-8 | Repo Isolation | Repositories must enforce `organization_id` on ALL read/write ops. |
| INV-9 | Evidence Sealing | Shaft-256 hashing at ingestion for ALL raw telemetry and files. |
| INV-10 | Error Visibility | Use `IntegrityException` for domain violations. No silent failures. |
| INV-11 | Skill Sealing | Mandatory "Step 0" Skill Insight before implementation. |
| INV-12 | Scanner Guard | Annotate non-currency doubles with `// Physical Metric - Double Required`. |
| INV-13 | Layer Bounds | C4 Compliance: Features MUST NOT import Domain or Infrastructure. |
| INV-14 | Adaptive Engine | Transport-agnostic Core: Use Asset/Operator/Execution. |
| INV-15 | Deterministic | Evaluation yields byte-identical results on replay. |
| INV-16 | Connection Ops | Supabase Free Tier: Max 60 concurrent connections. Design for pooling. |
| INV-17 | Wasm-Ready | Use `dart:js_interop` for Web. No legacy `dart:js` or `dart:html`. |
| INV-18 | Zero-Trust | Telmetry untrusted until normalized. Suspected spoofing quarantined. |
| INV-19 | JIT Workflows | Inline master data creation (Zones/Assets) in contract flows. |
| INV-20 | Shift Patterns | Use `DateTimeRange` + UTC normalization for all schedules. |
| INV-21 | Audit Trail | Every Engine verdict must carry a traceable Snapshot ID. |
| INV-22 | Multi-Tenancy | Tenant-A must NEVER see Tenant-B's data (test via Red Team tests). |
| INV-23 | Free-Tier First | All 3rd-party services must have a free tier for pre-revenue stage. |
| INV-24 | Security Guard | Mandatory `Security Audit Signature` for every agentic instruction. |
| INV-25 | Tech Stack | Supabase | MapTiler | Sentry | PostHog | Resend. SOC 2 compliant. |
| INV-26 | Error Parity | Security-sensitive endpoints MUST return identical status codes (404) for 'Not Found' and 'Other Org' to prevent data inference (Oracle Attacks). |
| INV-27 | Origin Ownership | Operations involving source-to-destination logic (Cloning/Transfers) MUST verify source ownership, treating unauthorized IDs as non-existent (404). |

---

## 🔄 EXECUTION PROTOCOLS

1.  **Mandatory Step 0 (The Forensic Pause):** Before proposing code, state:
    *   **Skill Insight:** Which `.claude/skills/` were consulted.
    *   **Invariant Check:** Which INV-X rules are relevant to this task.
2.  **Test-Driven Development (TDD):**
    *   Write a failing test (`IntegrityException` or logic) first.
    *   Implement minimal code to pass.
    *   Refactor with the Council's sign-off.
3.  **PR Scanner Pre-Flight:**
    *   Self-audit for `DateTime.now()` and unannotated `double`.
    *   Run `bash scripts/pr_full_scanner.sh`.
4.  **Consensus:** For structural changes, all council members (Architect, Senior, QA) must agree.

---

## 🛠️ TECH STANDARDS

### Dart & Flutter Web
- State Management: **Riverpod** (Generator required). Avoid `ChangeNotifier`.
- Projections: Use `AsyncValue` patterns for UI.
- Layouts: Constraint-based. Mobile-first. 24/7 Eye-Strain prevention (Industrial Deep palette).
- Web: Target WASM/CanvasKit. High performance for dashbaords.

### Supabase & Postgres
- Migrations: Pure idempotent SQL. NO `DROP` or destructive `ALTER` on prod.
- RLS: Enabled on EVERY table. Tenant-isolation is non-negotiable.
- Idempotency: Duplicate telemetry ingestion must return `200 OK` (Ignored) not `duplicate` error.

### AI & Agentic Rules (INV-11)
- Prompt Injection: All LLM summaries must pass through the `prompt-injection-auditor`.
- Sealing: Workflow outcomes must have a cryptographic/audit signature.

---

## 🚄 PERFORMANCE & BUDGET
- Model Priority: **Sonnet** (Development) | **Opus** (Review/Architecture).
- Memory: Prune old history. Move roadmap to `ROADMAP_HISTORY.md`.
- Token Efficiency: Use Tables > Bullet points > Paragraphs.
