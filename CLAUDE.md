# VeraProb - MASTER
SLA/Finance Protection. Forensic Governance.

## PROTOCOLS
1. TDD: Fail test (IntegrityException) BEFORE code.
2. DESIGN: Industrial Dark. Micro-anim, glassmorphism, 8pt, Inter/Outfit.
3. AUTONOMY: Proactive Council. Lead Reviewer for ALL PRs.
4. SCANNER: Run `bash scripts/security/pr_full_scanner.sh` BEFORE PR/Merge to Main. (Commits are free).

## COUNCIL PERSONAS
- Architect: Agnostic core, C4, Wasm.
- Senior: Flutter, Supabase/SQL, Perf.
- QA/Sec: Red Team, RLS, invariant.
- Reviewer: Gatekeeper. Final veto.
- UX/Ops: Frictionless, zero-touch.

## INVARIANTS (INV-1 to INV-28)
Consult Memory Server (entity: "VeraProb Invariants").
Must check before structural/domain edits.

---
## ORCHESTRATION (Makefile)
- `make setup` : Build env (DB/Seeds).
- `make run`   : Local dev.
- `make check` : Security/PR scan.
- `make help`  : List all cmds.

## COUNCIL
Architect, Senior, QA/Sec, UX/Ops, Reviewer.

---
## DOMAIN PROTOCOLS
- **SuperAdmin**: All multi-tenant escapes MUST use `SuperAdminBypassTenantValidator`. MFA enforcement is mandatory for sensitive state transitions (Archive/Quota/Delete).
- **Telegram**: Integration via `TelegramBindingToken` (short TTL). Evidence links must be strictly bound to `organization_id` to maintain INV-1 isolation.

---
## GUARDRAILS & HOOKS (Source: `hooks.json`)
Mandatory for ALL IDEs (Antigravity/Claude/Kiro). Failure to execute is a VETO.

| ID | Hook | Trigger | Action |
|---|---|---|---|
| H-01 | **TOKEN GUARD** | `preToolUse` | `.kiro/scripts/pre-tool-use.sh` (Auto-block >800 chars, node_modules). |
| H-02 | **TYPE SYNC** | `preCommit` | `bash scripts/sync_db_types.sh` (Dart/SQL Parity). |
| H-03 | **FORENSIC SCAN** | `preCommit` | `bash scripts/security/pr_full_scanner.sh` (Veto Gatekeeper). |
| H-04 | **SECRET SCAN** | `preCommit` | `python scripts/security/scan_secrets.py` (INV-28). |
| H-05 | **BARREL SCAN** | `preCommit` | `python scripts/validate_barrel_files.py` (INV-13). |
| H-06 | **PROMPT AUDIT** | `preCommit` | `skill://prompt-injection-auditor/audit-batch` (INV-41). |
| H-07 | **TDD ASSIST** | `onTestFail` | Senior Persona suggestion for fix. |
| H-08 | **CHAOS SUGGEST**| `onTestRun` | `skill://iot-chaos-simulator/auto-suggest`. |
| H-09 | **CACHE REFRESH**| `postSave` | `bash scripts/refresh_schema_cache.sh` (PostgREST sync). |
| H-10 | **MISSION SYNC**| `onMissionComplete` | `mcp:memory/sync_project_state` (Memory persistence). |
| H-11 | **INDEX ADVISOR**| `preCommit` | `python scripts/index_advisor.py` (INV-12). |
| H-12 | **CODE QUALITY** | `preCommit` | `dart fix --apply && flutter analyze` (Clean Code). |

---
## QUALITY CODE PROTOCOLS (Mandatory for Agents)
- **Zero-Waste**: Always run `dart fix --apply` after significant edits.
- **Strict Linting**: Treat all analyzer warnings as blockers (Errors in `analysis_options.yaml`).
- **Clean Imports**: No unused imports.
- **Dart Wildcards**: Use only a single `_` for ALL unused parameters (to avoid `unnecessary_underscores` errors).
- **Unused Locals**: Never leave unused local variables in tests or production code (enforced as error).
- **Prefer Const**: Always use `const` for constructors and declarations whenever possible.
- **Universal UTC (INV-6)**: `DateTime.now()` must ALWAYS be followed by `.toUtc()`. No exceptions.
- **Encoding & Line Endings**: All files MUST be **UTF-8 (LF)**. Integrity Guard will prevent commits if CRLF is detected (Crucial for Linux/Docker parity).
- **Hermetic Goldens**: Always use `make goldens` to update reference images (ensures Linux rendering parity).

---
## COMPLEXITY GATE (Forensic Thresholds)
Mandatory limits enforced by `scripts/security/analyze_dart_complexity.js`.

| Layer | LOC (Warn/Block) | CC (Warn/Block) | Nesting (Warn/Block) |
|---|---|---|---|
| **Domain/App** | 60 / 100 | 10 / 20 | 4 / 6 |
| **Infrastructure** | 100 / 200 | 15 / 25 | 5 / 7 |
| **Presentation** | 200 / 400 | 25 / 40 | 7 / 10 |
| **Tests** | 500 / 1000 | 50 / 100 | 10 / 15 |

