# Changelog

All notable changes to VeraProb will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-05-07
### Added
- Comprehensive forensic audit of the entire dependency graph (INV-25).
- 12 new Property-Based Tests (Glados) for State Engine resilience.

### Changed
- **Major**: Migrated State Management to **Riverpod v3** (Notifier API refactor).
- **Major**: Upgraded Database Layer to **Drift 2.33.0** and **Postgres 3.5.9**.
- **Security**: Hardened `ShiftPattern` logic to handle `timezone 0.11.0` breaking changes (Universal UTC).
- Updated CI/CD to align with Flutter 3.41.9 (Latest Stable Sync).

### Fixed
- Potential revenue leakage in Shadow Executions via strict Notifier lifecycle guards.

## [Unreleased] - Architectural Integrity Enforcement

### Added
- **Scanner rule `INFRA-LEAK-UI`** (BLOCK, INV-13): Prevents `lib/features/` from importing concrete `lib/infrastructure/` modules. Cross-cutting concerns (`observability/`, `config/`) are exempted. Enforces routing through application services and IRepository interfaces.
- **Scanner rule `GENERIC-EXCEPTION-DOMAIN`** (BLOCK, INV-10): Blocks `throw Exception(...)`, `throw StateError(...)`, `throw FormatException(...)`, and `throw TypeError(...)` in `lib/domain/` and `lib/application/`. Enforces typed domain exceptions (`IntegrityException`, `SovereigntyViolationException`, `ConflictException`, etc.).
- **`lib/infrastructure/analysis_options.yaml`**: Temporary per-directory strict-mode exemption for ~80 `Map<dynamic,dynamic>` cast violations in the infrastructure layer. Delete once violations are resolved via `scripts/audit_dynamic_types.sh`.

### Changed
- **`analysis_options.yaml`**: Activated `strict-casts`, `strict-inference`, and `strict-raw-types` globally (INV-7: Type Sovereignty). Domain, application, features, and state layers are now fully strict.
- **`CLAUDE.md` / `.kiro/rules.md`**: QUALITY CODE PROTOCOLS updated to document strict mode, layer shielding, and typed exception policies with scanner rule cross-references.

## [Unreleased] - Red Team v2.1 Remediation

### Security
- **CRITICAL:** Fixed atomicity gap in justification approval workflow (Red Team ID 2)
  - Replaced separate `updateStatusAtomic()` + `appendAuditLog()` calls with atomic RPC
  - Prevents race conditions where status changes without forensic audit trails
  - Eliminates "ghost deletions" where evidence is scheduled for removal despite concurrency conflicts
- **CRITICAL:** Added Magic Bytes validation to prevent malicious file uploads (Red Team ID 3)
  - Validates file types by reading binary signatures, not just extensions
  - Whitelist: JPEG, PNG, PDF, HEIC/HEIF, WebP
  - Rejects executables, SVG with scripts, and other malicious file types
- **CRITICAL:** Implemented XSS sanitization for user-submitted text (Red Team ID 4)
  - All `description` and `resolutionNotes` fields sanitized using `package:sanitize_html`
  - Strips all HTML tags, attributes, and JavaScript before persistence
  - Prevents script injection attacks in justification workflows
- **CRITICAL:** Implemented evidence lifecycle management and retention policies (Red Team ID 6)
  - Rejected/expired justifications now transition to **Cold Storage** after a 90-day active period.
  - `EvidenceLifecycleManager` automates archival and enforces 5-year forensic retention.
  - Prevents data loss while optimizing storage costs via tiered access.

### Added
- `justification_audit_logs` table with immutability triggers (INV-3)
  - Append-only audit trail for all status transitions
  - Full actor attribution (user_id, caller_role, timestamp_utc)
  - RLS enforces tenant isolation (INV-1)
- `evidence_retention_policy` configuration
  - Defines legal hold and archival rules per tenant
  - Service Role bypass required (INV-24) — standard users cannot modify policies
- `update_justification_status_with_audit` PostgreSQL RPC for atomic operations
  - Single transaction: status update + audit log + archival trigger
  - Concurrency-safe: returns 0 on conflict, entire transaction rolls back
  - SECURITY DEFINER with `SET search_path = public`
- `InputSanitizer` service using `package:sanitize_html` (Google)
  - Defense-in-Depth Layer 1: XSS protection at application boundary
  - Forensic guarantee: all stored text is plain text with no executable content
- `FileContentInspector` service with JPEG/PNG/PDF/HEIC/WebP validation
  - Defense-in-Depth Layer 2: Binary inspection before SHA-256 verification
  - HEIC signature detection at offset 4 (box length prefix)
  - Forensic guarantee: all evidence files match MIME whitelist
- `EvidenceLifecycleManager` for automated archival and compliance
  - Defense-in-Depth Layer 5: Enforces retention periods before any physical removal
  - Idempotent: failed transitions retry on next run, no silent data loss
  - Cost control: utilizes tiered storage for non-active evidence

### Changed
- `SLAJustificationRepository` interface updated with `updateStatusWithAuditLog` method
  - Deprecated `updateStatusAtomic` and `appendAuditLog` (separate calls create race conditions)
  - New method enforces atomic operations via PostgreSQL RPC
- `SLAJustificationManager` refactored to use defense-in-depth architecture
  - Layer 1: Input sanitization (XSS)
  - Layer 2: Binary inspection (Magic Bytes)
  - Layer 3: Cryptographic sealing (SHA-256, existing)
  - Layer 4: Atomic persistence (Transaction)
  - Layer 5: Lifecycle management (Archival/Retention)

### Dependencies
- Added `sanitize_html: ^2.1.0` for XSS protection

### Forensic Invariants
- **INV-1:** Multi-tenant isolation enforced on all new tables
- **INV-3:** Append-only audit logs (no UPDATE/DELETE)
- **INV-6:** UTC timestamps mandatory (all new tables use `timestamptz`)
- **INV-9:** Evidence sealing (SHA-256 + Magic Bytes)
- **INV-11:** Skill Sealing (Security Audit Signature on all new services)
- **INV-24:** Security Guard (hostile review completed before implementation)

### Skills Consulted
- `supabase-postgres-best-practices` (RLS, idempotent migrations, SECURITY DEFINER RPCs)
- `database-schema-design` (normalization, append-only patterns)
- `systematic-debugging` (root-cause analysis of race conditions)
- `security-best-practices` (XSS prevention, defense-in-depth)
- `hostile-defense-attorney` (adversarial validation of evidence integrity)

---

## [1.0.0] - 2026-04-15

### Initial Release
- Multi-tenant SLA audit engine
- Immutable ledger with forensic integrity
- Real-time telemetry ingestion
- Contract lifecycle management
- Evidence-based justification workflows
