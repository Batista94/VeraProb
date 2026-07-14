# VeraProb - Global Rules & Invariants

This file defines the non-negotiable rules and global static context for all agents and operations in VeraProb.

## 1. DEVELOPMENT PROTOCOLS
- **TDD (Test-Driven Development)**: Propose a failing test (throwing `IntegrityException`) BEFORE writing any implementation code.
- **DESIGN (Industrial Dark)**: 
  - Aesthetics: Premium dark mode, glassmorphism, industrial theme.
  - UI: 8pt grid, Inter/Outfit typography, micro-animations for feedback.
- **AUTONOMY**: Full proactivity. The agent "Council" must act without waiting for trivial instructions. The Lead Reviewer must audit all PRs.
- **SECURITY SCANNER**: Run `bash scripts/security/pr_full_scanner.sh` before any commit to a protected branch or merging to Main.

## 2. FORENSIC INVARIANTS (INV-1 to INV-28)
Invariants are the fundamental laws of VeraProb. No code change can violate them.
- **Single Source of Truth (SSOT)**: Always consult `.kiro/steering/forensic-standards.md` or `AGENTS.md`.
- **Automatic Verification**: The `preCommit` hook triggers the `forensic-scanner`, validating INV-1 to 28 via regex and static analysis.
- **Key Invariants**:
  - **INV-1 (Identity Sovereignty)**: All flows must validate and filter by `organization_id`.
  - **INV-6 (Universal UTC)**: Timestamps must use UTC. `TIMESTAMPTZ` mandatory in database.
  - **INV-19 (Penny Precision)**: Financial values must use `BIGINT` (cents), never `double`.
  - **INV-26 (Error Parity)**: Identical error codes (404) for Not Found and Wrong Org to prevent data inference.
  - **INV-28 (Secret Guard)**: Ban on committing credentials/secrets.
  - **INV-DB (Zero-Downtime)**: Ban on blocking DDL migrations.

## 3. ORCHESTRATION (Makefile)
Use standard commands to manage the environment:
- `make setup`: Builds the environment, database, and seeds.
- `make run`: Starts the local development server.
- `make check`: Runs the security scanner and forensic audit.
- `make help`: Lists all available targets.

## 4. CORE TECH STACK
- **Frontend**: Flutter.
- **Backend/DB**: Supabase (PostgreSQL + RLS).
- **Architecture**: Agnostic core, C4 patterns, Wasm integration.

---
## 5. DOMAIN PROTOCOLS
- **SuperAdmin**: Multi-tenant bypasses MUST use `SuperAdminBypassTenantValidator`. MFA is mandatory for sensitive state transitions (Archive/Quota/Delete).
- **Telegram**: Binding via `TelegramBindingToken` (short TTL). Evidence links strictly bound to `organization_id` (INV-1).

## 6. MEMORY GOVERNANCE (DPs)
STRICT MEMORY PROTOCOL for all agents:
- **Decision Points (DPs)**: Document choices impacting Forensic Invariants.
- **Format**: `DP-[ID]: [Context] -> [Decision] -> [Invariant Impact]`.
- **Example**: `DP-001: Migration to BigInt -> Impact INV-19 -> Reason: Financial precision.`

## 7. CLEAN CODE & LINTING (Agent Mandatory)
- **Analyzer Compliance**: Treat all `flutter analyze` warnings as blocking errors. Zero warnings, zero infos.
- **Strict Mode (INV-7)**: `strict-casts`, `strict-inference`, and `strict-raw-types` active globally. Infrastructure has temporary exemption in `lib/infrastructure/analysis_options.yaml` (~80 Map violations). Delete it when resolved.
- **Layer Shielding (INV-13)**: `lib/features/` must NEVER import `lib/infrastructure/` directly, except observability/config. Use application service or IRepository interface.
- **Typed Exceptions (INV-10)**: Never throw `Exception`, `StateError`, or `FormatException` in `lib/domain/` or `lib/application/`. Use: `IntegrityException`, `SovereigntyViolationException`, `ConflictException`, etc.
- **Dart Wildcards**: Use a single underscore `_` for unused parameters (prevents `unnecessary_underscores` lint).
- **Unused Code**: Remove unused variables and imports before committing.
- **Automated Fix**: Run `dart fix --apply` after significant changes.
- **Prefer Const**: Use `const` on constructors and widgets wherever possible.
- **Universal UTC (INV-6)**: `DateTime.now()` must always be followed by `.toUtc()`.

> **Lessons Learned** (Auth Lifecycle, Async Chain Isolation, Narrow Panels, E2E Protocols, Test CNPJ Factory, Regression Ack): consult [`.kiro/steering/lessons.md`](steering/lessons.md) — official Kiro steering file auto-loaded by all agents.

---
## 8. E2E TESTING GUIDELINES (MANDATORY)
- **Execution via Makefile**: All tests in `test/integration/e2e/**` must be executed via `make test-e2e` or `make test-e2e-file FILE=...`. Never run raw `flutter test` on E2E paths to avoid `pumpAndSettle` timeout.
- **Modal Management**: Modals with `barrierDismissible: false` block background taps. Close the modal via `cancelModal(tester)` before performing external navigation.
- **Selector Precision**: Verify the exact widget type (`TextField` vs `TextFormField`) and the literal button label from the screen source. Use `ValueKey` where available.
- **Valid Seed Data**: Use helper generators like `SuperAdminDataFactory.generateUniqueCnpj()` to produce valid CNPJs, otherwise validation will fail.
- **Zero Warnings**: Remove unused imports/variables in test files before committing to pass the linter.

---
## 9. COMPLEXITY GATE (Hard Limits)
Limits enforced by the forensic scanner to prevent technical debt.

| Layer | LOC (Warn/Block) | CC (Warn/Block) | Nesting (Warn/Block) |
|---|---|---|---|
| **Domain/App** | 60 / 100 | 10 / 20 | 4 / 6 |
| **Infrastructure** | 100 / 200 | 15 / 25 | 5 / 7 |
| **Presentation** | 200 / 400 | 25 / 40 | 7 / 10 |
| **Tests** | 500 / 1000 | 50 / 100 | 10 / 15 |
