# VeraProb — AGENTS.md

Universal context for AI coding agents. Follows [agents.md](https://agents.md/) spec. Read by Antigravity, Cursor, Codex, Aider, Gemini CLI, Kiro, and (via `@AGENTS.md` import) Claude Code.

> **Architecture:** AGENTS.md is the **navigation index**. Each rule has ONE source-of-truth file (linked below). Update only the source; `make docs-check` validates the index stays in sync.

## Mission

SLA/Finance Protection + Forensic Governance for high-frequency operational telemetry. Acts as an Agnostic Forensic Engine: ingests raw telemetry, ranks evidence, issues immutable verdicts auditable in <10 seconds.

> [!IMPORTANT]
> **Enterprise Directive:** This project is NOT an MVP. Avoid any code, architectural, or testing shortcuts justified by "MVP simplifications". Implement production-ready, highly reliable, and enterprise-grade B2B solutions.


## Stack

- **Frontend:** Flutter (Wasm/CanvasKit), Riverpod Generator.
- **Design System:** Industrial Dark palette (Slate/Zinc `#0F172A`), glassmorphism, micro-animations, Inter/Outfit typography, 8pt grid. Forbidden: pure-white, generic AI aesthetics, vibrant non-semantic colors. Semantic financial coloring: Emerald (Savings), Red (Penalties), Amber (Risk).
- **Backend:** Supabase (PostgreSQL + RLS), Edge Functions, MapTiler, PostHog, Sentry, Resend.
- **Architecture:** Clean Architecture (C4 boundaries), Append-only ledger, Zero-Trust telemetry.

## Setup

```bash
make setup          # build env (DB, seeds, types)
make run            # local dev (web)
make test           # unit + widget suite (sequential -j 1)
make test-db        # pgTap forensic DB tests
make test-all       # test + test-db (no E2E)
make test-e2e       # E2E suite (auto-applies required dart-defines)
make test-e2e-file FILE=path/to/test.dart
make test-full      # test-all + test-e2e (requires local Supabase up)
make goldens        # hermetic Linux Docker (NEVER update goldens outside this target)
make format         # dart format via hermetic Docker
make check          # check-integrity + scan-secrets + pr-scan + index-advisor + format-check
make docs-check     # validate AGENTS.md index matches source files
make full-check     # check FULL_SCAN=1 + test-full (incl. E2E, requires local Supabase) + chaos-test + coverage
make help           # list all targets
```

## Forensic Invariants (INV-1 to INV-28)

Full table SSOT: [`.kiro/steering/forensic-standards.md`](.kiro/steering/forensic-standards.md). Check before ANY structural/domain edit.

Critical subset:

| ID | Rule |
|----|------|
| INV-1 | `organization_id` filter on ALL flows + JWT claim validation (Fail-Fast) |
| INV-2 | RLS uses `auth.jwt() ->> 'organization_id'`, NEVER `auth.uid()` |
| INV-3 | Ledger/Finance APPEND-ONLY (no UPDATE/DELETE) |
| INV-4 | Money: `BIGINT` cents (DB), `int` (DTO), `Money` VO (Domain) |
| INV-6 | UTC mandatory (`TIMESTAMPTZ` + `IDateTimeProvider.nowUtc()`) |
| INV-7 | No `dynamic`. Strict types. |
| INV-10 | Typed domain exceptions — never `Exception/StateError/FormatException` in domain/application |
| INV-13 | C4: `lib/features/` MUST NOT import `lib/infrastructure/` (except `observability/`, `config/`) |
| INV-22 | Tenant isolation: Tenant-A NEVER sees Tenant-B. Red-Team tested. |
| INV-26 | Error parity: 404 for Not Found AND Wrong Org (Anti-Oracle) |
| INV-28 | Org secret isolation (HMAC per org) |

## Code Style

- `dart fix --apply` after every significant edit (Zero-Waste).
- Zero `flutter analyze` warnings — blockers (Strict Linting; errors in `analysis_options.yaml`).
- Clean Imports: no unused imports.
- Unused Locals: never leave unused locals in tests or production code (enforced as error).
- Files `kebab-case`, types `PascalCase`, members `camelCase`.
- Encoding UTF-8 LF mandatory (CRLF blocked — Linux/Docker parity). AI agents MUST ensure all generated or edited files use LF (`\n`) exclusively, even on Windows.
- `const` whenever possible.
- Unused params: single `_` (avoid `unnecessary_underscores` error).
- `DateTime.now()` MUST be followed by `.toUtc()` (INV-6).
- Hermetic Goldens: always `make goldens` (Linux Docker — CI parity). Goldens live in ONE dedicated `*_golden_test.dart` per widget, registered in `scripts/generate_goldens.sh` `TEST_FILES` in the same diff — unregistered goldens never get a baseline (GOLDEN-UNWIRED, ci-blocks #19).
- **No IIFE in UI (IIFE-UI-SMELL):** Never use `() { ... }()` inside `build` or `switch` statements. Always extract to helper methods (`_buildX`).
- **No raw exceptions in UI (UX-RAW-EXCEPTION):** Never display `$e`, `e.toString()`, or state-wrapper errors (`${actionState.error}`, `${asyncValue.error}`, `${snapshot.error}`) in SnackBars/Text. Map to domain vocabulary. Scanner does NOT catch these — review-enforced.
- **Accent-fill contrast (ACCENT-FILL-CONTRAST):** Foreground on `primary`/`secondary`/`error` fills is always `VeraProbColors.background` (dark), never `Colors.white` — white fails WCAG AA 4.5:1 on all Indigo Zinc accents. Encoded in theme; don't override at widget level.
- **Wasm Context Leaks (WASM-CONTEXT-LEAK):** Capture `ScaffoldMessenger.of(context)` BEFORE any `await`. Never use `if (mounted)` with `context` after an `await`.
- **UI Clean Code:** Avoid nested ternary operators. Keep `build()` methods declarative; push business logic into Riverpod providers. Use `VeraProbColors` and `VeraProbTypography` instead of hardcoded styling.
- **Ponytail (Lazy Senior Dev Philosophy):** Avoid over-engineering. Question speculative or unrequested abstractions (no interfaces with single implementations, no factories for one product). Keep Domain VOs minimal (no database audit metadata like hashes/versions/timestamps unless used in the UI). Avoid redundant widget helpers or nested layouts (inlining simple elements). Prioritize native platform features, standard libraries, and existing dependencies before writing custom code. Shortest working diff wins, but do NOT simplify away safety, UTC rules, bigints, database security/RLS, or tenant isolation.
- **Enterprise Simplicity (YAGNI & Senior Heuristics):**
  1. *Model Reusability:* Query the codebase before creating new domain models or enums; extend existing models instead of writing duplicates.
  2. *Pragmatic Mapping:* Do not introduce separate DTO/entity mapping layers if the database payload and domain entity are structural identical and simple.
  3. *Local vs. Global State:* Keep local UI states (tabs, search queries, panel states) in widget-local state (`StatefulWidget`/`flutter_hooks`); restrict Riverpod to shared, async, or database-backed state.
  4. *Behavioral Testing:* Test business rules, domain exceptions, and state transitions. Avoid writing trivial tests that only assert constructor parameters or mocks.
  5. *Rule of Three:* Extract widgets/helpers to `shared/` only if they are used in 3+ places. Otherwise, keep them inline or feature-scoped.


## Protocols (Mandatory)

1. **TDD:** Failing test (`IntegrityException`) BEFORE implementation code.
2. **Step 0:** State Skill Insight + relevant INV-X before any code change.
3. **Scanner:** `bash scripts/security/pr_full_scanner.sh` MUST pass before PR/merge to main. Commits to feature branches are free.
4. **Proactive Council:** Architect + Senior + QA/Sec sign-off for structural changes; Lead Reviewer is the final gate. Agents act autonomously without waiting for trivial commands.

## Common CI Blocks — Index

Full fix recipes SSOT: [`.claude/rules/ci-blocks.md`](.claude/rules/ci-blocks.md) (auto-loads when Claude edits `lib/**/*.dart`, `test/**/*.dart`, `supabase/migrations/**`).

| # | ID | Pattern |
|---|------|---------|
| 1 | INV-DB | Zero-Downtime Migration (no blocking ALTER/DROP/DELETE/TRUNCATE) |
| 2 | INFRA-LEAK-UI | `lib/features/` importing concrete `lib/infrastructure/` |
| 3 | GENERIC-EXCEPTION-DOMAIN | `throw Exception/StateError/FormatException` in domain/application |
| 4 | UTC-BLOCK | `DateTime.now()` without `.toUtc()` |
| 5 | AUTH-TRAP | SignOut leaves user on NotFoundPage (missing global redirect) |
| 6 | CATCH-SWALLOW | Unified `try/catch` discards valid result of independent async call |
| 7 | RENDERFLEX-NARROW | Header overflow in narrow panels |
| 8 | E2E-HANG | E2E `pumpAndSettle` timeout (missing dart-defines) |
| 9 | E2E-HTTPMOCK | `HttpOverrides` ignored by pre-initialized Supabase HttpClient |
| 10 | E2E-SELECTOR | Test selector mismatch (TextField vs TextFormField, label inference) |
| 11 | SECURITY-DEFINER-VIEW | `CREATE VIEW` without `WITH (security_invoker = true)` bypasses RLS (INV-2, INV-22) |
| 12 | PARTITION-RLS-GAP | `CREATE TABLE … PARTITION OF` without per-child `ENABLE ROW LEVEL SECURITY` + mirrored policy (INV-2, INV-22) |
| 13 | INV-DATA-API-GRANT | Missing explicit Data API table grants for tables created in the `public` schema |
| 14 | LAZY-TEST-BYPASS | Mock/Empty pgTAP Tests |
| 15 | WASM-CONTEXT-LEAK | `ScaffoldMessenger.of(context)` or `Navigator.of(context)` used after `await` |
| 16 | IIFE-UI-SMELL | `() { ... }()` Immediately Invoked Function Expressions in UI |
| 17 | UX-RAW-EXCEPTION | Error object interpolated in UI text (`$e`, `e.toString()`, `${state.error}`, `${asyncValue.error}`) |
| 18 | ACCENT-FILL-CONTRAST | `Colors.white` foreground on accent fills (primary/secondary/error) fails WCAG AA — use `background` |
| 19 | GOLDEN-UNWIRED | `goldenTest` in file absent from `generate_goldens.sh` TEST_FILES — baseline never generated |
| 20 | NUM-CLAMP-DOWNCAST | `num.clamp` result passed to `double` parameter — implicit downcast blocked by Strict Mode |
| 21 | ALWAYS-TRUE-RLS-POLICY | PERMISSIVE `USING(true)` for client roles — use Global Catalog RLS Pattern or org predicate |
| 22 | OVER-ENGINEERING | Speculative properties and UI nesting |

## Lessons Learned — Index

Full Why/How SSOT: [`.kiro/steering/lessons.md`](.kiro/steering/lessons.md) (Kiro auto-loads via `inclusion: auto`).

| # | Topic |
|---|-------|
| 1 | Auth Lifecycle — guarded screens require global `signedOut` redirect in `lib/main.dart` |
| 2 | Async Chain Isolation — per-call `.catchError`, never unified try/catch |
| 3 | Narrow Panel Layouts — `Flexible` + `ellipsis` + short label + `Tooltip` in panels `maxWidth <= 320px` |
| 4 | Conscious BarrierDismissible — `barrierDismissible: false` requires explicit modal close before navigation |
| 5 | Clear Error Messaging — no `[DBG]` prefixes, no stack traces, domain-language only |
| 6 | E2E Test Protocols — dart-defines, selectors, HttpOverrides, modal cancel, CNPJ factory |
| 7 | Regression Ack Discipline — `// pr_scanner: ignore-regression` only after Council review |
| 8 | Flutter Web Wasm Async Context — capture `Navigator.of(context)` + `ScaffoldMessenger.of(context)` BEFORE first `await` in dialogs; add `_isSaving` guard to prevent ClickDebouncer loop (CT02) |
| 9 | Automated Test Synchronization — update automated tests when code is modified to prevent stale test errors |
| 10 | No IIFE in Widget Trees — avoid immediately invoked function expressions in build or switch |
| 11 | No Raw Exceptions in UI — map errors to domain vocabulary (incl. `${state.error}` wrappers), avoid hardcoded styling |
| 12 | Accent-Fill Foreground Contrast — dark `background` foreground on accent fills, never `Colors.white`; validate token pairs both directions |
| 13 | Golden Test Wiring — goldens live in ONE `*_golden_test.dart` registered in `generate_goldens.sh` TEST_FILES, else baseline never generated |
| 14 | Security-Flow SSOT — reveal-once/destructive dialog flows have one owner (screen); extracted widgets get callbacks, never copies |
| 15 | Over-engineering & Speculative Fields — Keep Domain VOs minimal, avoid redundant UI nesting, delete trivial constructor tests |


## Database Governance

- Append-Only migrations. Never modify a merged `.sql` file.
- Every new `supabase/migrations/*.sql` requires a matching `forensic_records/plans/{timestamp}*_test_plan.md` **and** `supabase/tests/{timestamp}*_test.sql` (both 1:1 per migration timestamp — consolidating multiple migrations into one pgTAP file does not satisfy the scanner).
- `supabase/types.database.ts` regenerated + committed with any migration.
- **Global Catalog RLS Pattern:** shared reference tables use `organization_id UUID` nullable (`NULL` = global row). Policy: `organization_id IS NULL OR organization_id matches JWT` — never `USING(true)`. SSOT: `20260813000004_dispute_reason_codes.sql`.
- No blocking ALTER — use 3-step CHECK NOT VALID → VALIDATE → SET NOT NULL pattern. Full recipe in [`.claude/rules/ci-blocks.md`](.claude/rules/ci-blocks.md) #1.
- Destructive DDL (DROP TABLE/COLUMN, DELETE, TRUNCATE) blocked. Requires `-- INV-DB: zero-downtime-verified` bypass comment after Council approval.
- Soft-delete only (`deleted_at` or archive status). No hard `DELETE`.
- All datetime columns: `TIMESTAMPTZ` mandatory. Bare `TIMESTAMP` blocked.
- **Views (INV-2):** ALL `public` schema views MUST be created with `WITH (security_invoker = true)`. Omitting this defaults to SECURITY DEFINER, which bypasses RLS on underlying tables. Full recipe in [`.claude/rules/ci-blocks.md`](.claude/rules/ci-blocks.md) #11.
- **Partitions (INV-2):** `ENABLE ROW LEVEL SECURITY` does NOT cascade to hash/range/list partitions. Every `CREATE TABLE … PARTITION OF` MUST immediately enable RLS and mirror the parent policy on the child. Full recipe in [`.claude/rules/ci-blocks.md`](.claude/rules/ci-blocks.md) #12.
- **Explicit Grants (INV-DATA-API-GRANT):** New tables in the `public` schema have no default privileges. They MUST explicitly grant required permissions (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) to the API roles (`authenticated`, `anon`, `service_role`). Full recipe in [`.claude/rules/ci-blocks.md`](.claude/rules/ci-blocks.md) #13.

## Complexity Gates (Hard Limits)

| Layer | LOC (Warn/Block) | CC (Warn/Block) | Nesting (Warn/Block) |
|-------|------------------|-----------------|----------------------|
| Domain/App | 60 / 100 | 10 / 20 | 4 / 6 |
| Infrastructure | 100 / 200 | 15 / 25 | 5 / 7 |
| Presentation | 200 / 400 | 25 / 40 | 7 / 10 |
| Tests | 500 / 1000 | 50 / 100 | 10 / 15 |

## Test Layout

- `test/` — unit + widget (`make test`)
- `test/integration/` — DB-backed (sequential)
- `test/integration/e2e/superadmin/` — E2E (`make test-e2e`)
- `supabase/tests/` — pgTAP forensic DB (`make test-db`)

## Out-of-Scope (Do NOT)

- Don't add features, refactors, or abstractions beyond the task.
- Don't add validation/error handling for impossible scenarios. Validate at boundaries.
- Don't write comments explaining WHAT — only WHY when non-obvious.
- Don't create docs (`*.md`) unless explicitly requested.
- Don't commit unless user explicitly asks.
- Don't bypass scanner with `--no-verify` or silence rules.
- Don't modify already-merged migrations (append-only).
- Don't use "lazy" workarounds. Lazy testing (e.g., bypassing assertions, mocking pgTAP), lazy fixes (silencing linters instead of fixing root causes), and taking shortcuts are strictly forbidden.

## Where to Look (Source-of-Truth Map)

| Topic | SSOT File | When loaded |
|-------|-----------|-------------|
| 28 Forensic Invariants | [`.kiro/steering/forensic-standards.md`](.kiro/steering/forensic-standards.md) | Kiro inclusion auto |
| 10 CI Block fix recipes | [`.claude/rules/ci-blocks.md`](.claude/rules/ci-blocks.md) | Claude path-scoped (`.dart`/`.sql`) |
| 7 Lessons (Why/How) | [`.kiro/steering/lessons.md`](.kiro/steering/lessons.md) | Kiro inclusion auto |
| Design system details | [`.kiro/steering/ux-standards.md`](.kiro/steering/ux-standards.md) | Kiro inclusion auto |
| Hooks (12 preCommit/preToolUse) | [`hooks.json`](hooks.json) + [`CLAUDE.md`](CLAUDE.md) | Always (executed) |
| Council agent invocation | [`.claude/agents/*.md`](.claude/agents/) + [`.kiro/agents/*.md`](.kiro/agents/) | On task match |
| Claude Code specifics | [`CLAUDE.md`](CLAUDE.md) | Claude session start |
| Orchestration | [`Makefile`](Makefile) | `make` invocation |
| Scanner | [`scripts/security/pr_full_scanner.sh`](scripts/security/pr_full_scanner.sh) | preCommit + manual |

**Rule:** edit ONLY the SSOT file. Run `make docs-check` before commit to validate index drift.
