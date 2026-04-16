# Changelog

All notable changes to VeraProb will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- **CRITICAL:** Added evidence lifecycle management to prevent storage cost leaks (Red Team ID 6)
  - Rejected/expired justifications now schedule evidence for deletion after 7-day grace period
  - `JustificationJanitorService` automates cleanup of orphaned files
  - Prevents unbounded storage growth from abandoned justifications

### Added
- `justification_audit_logs` table with immutability triggers (INV-3)
  - Append-only audit trail for all status transitions
  - Full actor attribution (user_id, caller_role, timestamp_utc)
  - RLS enforces tenant isolation (INV-1)
- `evidence_deletion_queue` table with 7-day grace period
  - Soft-delete pattern allows recovery before permanent removal
  - Service Role bypass required (INV-24) — standard users cannot query pending deletions
- `update_justification_status_with_audit` PostgreSQL RPC for atomic operations
  - Single transaction: status update + audit log + deletion queue
  - Concurrency-safe: returns 0 on conflict, entire transaction rolls back
  - SECURITY DEFINER with `SET search_path = public`
- `InputSanitizer` service using `package:sanitize_html` (Google)
  - Defense-in-Depth Layer 1: XSS protection at application boundary
  - Forensic guarantee: all stored text is plain text with no executable content
- `FileContentInspector` service with JPEG/PNG/PDF/HEIC/WebP validation
  - Defense-in-Depth Layer 2: Binary inspection before SHA-256 verification
  - HEIC signature detection at offset 4 (box length prefix)
  - Forensic guarantee: all evidence files match MIME whitelist
- `JustificationJanitorService` for automated evidence cleanup
  - Defense-in-Depth Layer 5: Lifecycle management after atomic persistence
  - Idempotent: failed deletions retry on next run, no silent data loss
  - Cost control: prevents unbounded storage growth

### Changed
- `SLAJustificationRepository` interface updated with `updateStatusWithAuditLog` method
  - Deprecated `updateStatusAtomic` and `appendAuditLog` (separate calls create race conditions)
  - New method enforces atomic operations via PostgreSQL RPC
- `SLAJustificationManager` refactored to use defense-in-depth architecture
  - Layer 1: Input sanitization (XSS)
  - Layer 2: Binary inspection (Magic Bytes)
  - Layer 3: Cryptographic sealing (SHA-256, existing)
  - Layer 4: Atomic persistence (Transaction)
  - Layer 5: Lifecycle management (Janitor)

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
