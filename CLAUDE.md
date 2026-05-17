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
- **Strict Mode (INV-7)**: `strict-casts`, `strict-inference`, `strict-raw-types` are ENABLED globally. Infrastructure layer has a temporary exemption in `lib/infrastructure/analysis_options.yaml` until ~80 `Map<dynamic,dynamic>` cast violations are resolved. Delete that file once clean.
- **Layer Shielding (INV-13)**: `lib/features/` MUST NOT import `lib/infrastructure/` except `observability/` and `config/` (cross-cutting concerns). Route via application service or IRepository interface. Scanner rule: `INFRA-LEAK-UI`.
- **Typed Exceptions**: Never `throw Exception(...)`, `throw StateError(...)`, or `throw FormatException(...)` in `lib/domain/` or `lib/application/`. Use: `IntegrityException`, `SovereigntyViolationException`, `ConflictException`, `AuthorizationException`, `ResourceNotFoundException`, etc. Scanner rule: `GENERIC-EXCEPTION-DOMAIN`.
- **Clean Imports**: No unused imports.
- **Dart Wildcards**: Use only a single `_` for ALL unused parameters (to avoid `unnecessary_underscores` errors).
- **Unused Locals**: Never leave unused local variables in tests or production code (enforced as error).
- **Prefer Const**: Always use `const` for constructors and declarations whenever possible.
- **Universal UTC (INV-6)**: `DateTime.now()` must ALWAYS be followed by `.toUtc()`. No exceptions.
- **Encoding & Line Endings**: All files MUST be **UTF-8 (LF)**. Integrity Guard will prevent commits if CRLF is detected (Crucial for Linux/Docker parity).
- **Hermetic Goldens**: Always use `make goldens` to update reference images (ensures Linux rendering parity).

---
## DATABASE GOVERNANCE (INV-DB)
Mandatory Zero-Downtime patterns to prevent table locks:
- **Append-Only Migrations**: NEVER modify a `.sql` file already merged to main. All DB changes require a new sequential migration file.
- **Mandatory Test Plan**: Every new `supabase/migrations/*.sql` MUST be accompanied by a matching `forensic_records/plans/{timestamp}*_test_plan.md` in the same PR (scanner Step 9.1 enforces 1:1 prefix match).
- **Type Sync**: `supabase/types.database.ts` MUST be regenerated and committed in the same PR as any migration change (scanner Step 4, H-02 hook).
- **Avoid Blocking ALTER**: Never use `ALTER COLUMN ... SET NOT NULL` directly on large tables.
- **Destructive DDL Prohibited**: `DROP TABLE`, `DROP COLUMN`, `DELETE FROM`, `TRUNCATE` are blocked by scanner (INV-DB). Require `-- INV-DB: zero-downtime-verified` bypass comment after Council approval.
- **Safe Pattern**: 
  1. Add `CHECK CONSTRAINT (col IS NOT NULL) NOT VALID`.
  2. `VALIDATE CONSTRAINT` (non-blocking).
  3. `ALTER COLUMN ... SET NOT NULL` (safe after validation).
  4. `DROP CONSTRAINT`.
- **Soft-Delete**: Never use `DELETE`. Use `deleted_at` or archive status (INV-7).
- **Timestamps**: All datetime columns MUST use `TIMESTAMPTZ`. Bare `TIMESTAMP` is blocked by scanner (INV6-TIMESTAMP-TZ, INV6-BARE-TIMESTAMP-SQL).

---
## COMPLEXITY GATE (Forensic Thresholds)
Mandatory limits enforced by `scripts/security/analyze_dart_complexity.js`.

| Layer | LOC (Warn/Block) | CC (Warn/Block) | Nesting (Warn/Block) |
|---|---|---|---|
| **Domain/App** | 60 / 100 | 10 / 20 | 4 / 6 |
| **Infrastructure** | 100 / 200 | 15 / 25 | 5 / 7 |
| **Presentation** | 200 / 400 | 25 / 40 | 7 / 10 |
| **Tests** | 500 / 1000 | 50 / 100 | 10 / 15 |

---
## COMMON CI BLOCKS & FORENSIC FIXES

### 1. INV-DB: Zero-Downtime Migration
**Problem:** Direct `ALTER COLUMN SET NOT NULL`, `DROP COLUMN`, `DROP TABLE`, `DELETE FROM`, or `TRUNCATE` on active tables.

**Fix for SET NOT NULL (3-Step Pattern):**
```sql
-- 1. Add CHECK NOT VALID
ALTER TABLE table_name ADD CONSTRAINT col_not_null CHECK (col IS NOT NULL) NOT VALID;
-- 2. Validate (Safe Scan)
ALTER TABLE table_name VALIDATE CONSTRAINT col_not_null;
-- 3. Set NOT NULL with Bypass Comment
ALTER TABLE table_name ALTER COLUMN col SET NOT NULL; -- INV-DB: zero-downtime-verified
```
*Note: The comment `-- INV-DB: zero-downtime-verified` MUST be on the same line as the offending DDL.*

**Fix for DROP COLUMN:** Use soft-deprecation — add `_deprecated` suffix, stop writing, migrate reads. Only `DROP COLUMN` after next release cycle with Council approval and bypass comment.

**Fix for DELETE/TRUNCATE:** Use `deleted_at` soft-delete (INV-7). No hard deletes.

### 2. INFRA-LEAK-UI: Infrastructure import in Features layer
**Problem:** `lib/features/` directly imports a concrete `lib/infrastructure/` module (repository or service).
**Fix:** Route through application service or inject via interface:
```dart
// Wrong — features importing infrastructure directly
import 'package:veraprob/infrastructure/sla_audit/justification/file_service/justification_file_service.dart';

// Right — inject interface via Riverpod provider
final service = ref.read(justificationFileServiceProvider);
```
*Exception: `infrastructure/observability/` (logger) and `infrastructure/config/` (environment) are permitted cross-cutting concerns.*

### 3. GENERIC-EXCEPTION-DOMAIN: Generic exception in domain/application
**Problem:** `throw Exception(...)`, `throw StateError(...)`, or `throw FormatException(...)` in domain/application layers.
**Fix:** Use typed domain exception:
```dart
// Wrong
throw StateError('Contract already finalized');
throw FormatException('Invalid UUID: $raw');

// Right
throw IntegrityException('Contract already finalized', field: 'status');
throw IntegrityException('Invalid UUID', field: 'id');
```
*Available exceptions: `IntegrityException`, `SovereigntyViolationException`, `ConflictException`, `AuthorizationException`, `ResourceNotFoundException`, `IdempotencyProcessingException`.*

### 4. UTC-BLOCK: DateTime.now()
**Problem:** Use of local time instead of universal time.
**Fix:**
```dart
// Wrong
final now = DateTime.now();
// Right
final now = DateTime.now().toUtc();
```
*Note: In tests, if you need to simulate local time, use `DateTime.now().toUtc().toLocal()` to satisfy the scanner while achieving the offset.*

