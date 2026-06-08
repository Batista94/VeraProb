@AGENTS.md

# VeraProb — Claude Code Instructions

This file imports `AGENTS.md` (universal context) above and appends Claude Code-specific configuration below. Source of truth for stack/INVs/CI Blocks/protocols is `AGENTS.md`.

---

> **CRITICAL AGENT RULE:** All AI-generated or edited files MUST use LF (`\n`) exclusively for line endings, even on Windows. CRLF is strictly blocked and will fail the Integrity Guard.

---

## ORCHESTRATION (Makefile)

Full target catalog in `AGENTS.md` "Setup" section. Claude-relevant highlights:

- `make setup` / `make run` — env + dev server
- `make test` / `make test-db` / `make test-all` — fast cycles
- `make test-e2e` / `make test-e2e-file FILE=...` — E2E with required dart-defines
- `make test-full` — everything (requires local Supabase up)
- `make goldens` — hermetic via Docker Linux (NEVER update goldens outside this target — CI parity)
- `make check` / `make full-check` — scanner + lint + (optional) chaos + coverage
- `make help` — list all targets

## COUNCIL PERSONAS (sub-agent invocation triggers)

| Persona | Trigger | Definition |
|---------|---------|------------|
| **Architect** | New domain entities, layer boundaries, Agnostic Core refactor | [`.claude/agents/architect.md`](.claude/agents/architect.md) |
| **Senior Engineer** | Implementation, Riverpod, SQL migrations, performance, bug fixes | [`.claude/agents/senior-engineer.md`](.claude/agents/senior-engineer.md) |
| **QA/Security** | DB schema, RLS, RBAC, idempotency, telemetry, evidence handling | [`.claude/agents/qa-security.md`](.claude/agents/qa-security.md) |
| **UX/Operations** | OCC screens, penalty display, forensic reports, dispatcher/CFO flows | [`.claude/agents/ux-operations.md`](.claude/agents/ux-operations.md) |
| **Lead Reviewer** | PR merge gatekeeper, runs full scanner, applies 27 Core Invariants | [`.claude/agents/lead-reviewer.md`](.claude/agents/lead-reviewer.md) |
| **Business Maverick** | ROI evaluation, feature priority, margin-erosion analysis | [`.claude/agents/business-maverick.md`](.claude/agents/business-maverick.md) |

Invoke proactively when task matches scope. See each agent's frontmatter `description` for exact triggers.

## DOMAIN-SPECIFIC PROTOCOLS

- **SuperAdmin:** All multi-tenant escapes MUST use `SuperAdminBypassTenantValidator`. MFA enforcement mandatory for sensitive state transitions (Archive/Quota/Delete).
- **Telegram:** Integration via `TelegramBindingToken` (short TTL). Evidence links strictly bound to `organization_id` (INV-1).
- **E2E Testing:** Any changes/fixes to `test/integration/e2e/**` MUST:
  - Run using `make test-e2e` or `make test-e2e-file FILE=...` (never raw `flutter test` due to `--dart-define=SKIP_MFA_DEV=true` requirement to avoid `pumpAndSettle` timeout).
  - Explicitly close modals via `cancelModal(tester)` before performing external navigation or clicking widgets through the modal barrier.
  - Verify selectors against actual widget types and literal labels in the screen file.
  - Eliminate all static analysis warnings/unused variables.


## GUARDRAILS & HOOKS (Source: `hooks.json`)

Mandatory for all IDEs (Antigravity/Claude/Kiro). Failure to execute = VETO.

| ID | Hook | Trigger | Action |
|----|------|---------|--------|
| H-01 | TOKEN GUARD | `preToolUse` | `.kiro/scripts/pre-tool-use.sh` (auto-block >800 chars, node_modules) |
| H-02 | TYPE SYNC | `preCommit` | `bash scripts/sync_db_types.sh` (Dart/SQL parity) |
| H-03 | FORENSIC SCAN | `preCommit` | `bash scripts/security/pr_full_scanner.sh` (Veto Gatekeeper) |
| H-04 | SECRET SCAN | `preCommit` | `python scripts/security/scan_secrets.py` (INV-28) |
| H-05 | BARREL SCAN | `preCommit` | `python scripts/validate_barrel_files.py` (INV-13) |
| H-06 | PROMPT AUDIT | `preCommit` | `skill://prompt-injection-auditor/audit-batch` (INV-41) |
| H-07 | TDD ASSIST | `onTestFail` | Senior Persona suggestion for fix |
| H-08 | CHAOS SUGGEST | `onTestRun` | `skill://iot-chaos-simulator/auto-suggest` |
| H-09 | CACHE REFRESH | `postSave` | `bash scripts/refresh_schema_cache.sh` (PostgREST sync) |
| H-10 | MISSION SYNC | `onMissionComplete` | `mcp:memory/sync_project_state` (Memory persistence) |
| H-11 | INDEX ADVISOR | `preCommit` | `python scripts/index_advisor.py` (INV-12) |
| H-12 | CODE QUALITY | `preCommit` | `dart fix --apply && flutter analyze` (Clean Code) |

## SCANNER PROTOCOLS

- Run `bash scripts/security/pr_full_scanner.sh` BEFORE every PR/merge to main. Commits to feature branches are free.
- Scanner detects: GENERIC-EXCEPTION-DOMAIN, INFRA-LEAK-UI, UTC-BLOCK, INV-DB violations, regression on `lib/domain/**` + `supabase/migrations/**`.
- **Regression Ack:** scanner flags any modified file in `lib/domain/**` or `supabase/migrations/**` as `Regression Alert`. Two acceptable responses: (a) Council-approved `// pr_scanner: ignore-regression` comment, or (b) revert. Auto-acking without Council review = process violation.

## STRICT MODE & LAYER SHIELDING (project-specific)

- **Strict Mode (INV-7):** `strict-casts`, `strict-inference`, `strict-raw-types` ENABLED globally. Infrastructure has temporary exemption in `lib/infrastructure/analysis_options.yaml` until ~80 `Map<dynamic,dynamic>` cast violations are resolved. Delete that file once clean.
- **Layer Shielding (INV-13):** Route `lib/features/` → `lib/infrastructure/` via application service or `IRepository` interface. Exceptions: `infrastructure/observability/` (logger), `infrastructure/config/` (env). Scanner rule: `INFRA-LEAK-UI`.

## PATH-SCOPED RULES (auto-loaded by file pattern)

Loaded when Claude edits matching files:

- [`.claude/rules/ci-blocks.md`](.claude/rules/ci-blocks.md) — Common CI Block fix recipes (loads on `lib/**/*.dart`, `test/**/*.dart`, `supabase/migrations/**/*.sql`)

## STEERING (Kiro-aligned, advisory for Claude)

- [`.kiro/steering/forensic-standards.md`](.kiro/steering/forensic-standards.md) — full 28 Invariants
- [`.kiro/steering/lessons.md`](.kiro/steering/lessons.md) — runtime/test/UX heuristics from solved bugs
- [`.kiro/steering/ux-standards.md`](.kiro/steering/ux-standards.md) — Industrial Dark design system

## PERFORMANCE & BUDGET

- Models: Sonnet (dev) | Opus (architecture/review).
- Memory: prune history. Roadmap → `ROADMAP_HISTORY.md`.
- Tokens: tables > bullets > paragraphs.
