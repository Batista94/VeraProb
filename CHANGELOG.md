# Changelog

All notable changes to VeraProb will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - Phase 10.6: Ingestion Health Monitor & Signal Integrity

Branch `feature/sparklines`. Uncommitted.

### Added

- **Ingestion Health Monitor screen** (`IngestionHealthScreen`): real-time fleet connectivity dashboard with per-vehicle telemetry gap analysis. Sorted worst-first by RPC (`get_fleet_health_status` SECURITY DEFINER — INV-1, INV-2, INV-26).
- **`FleetHealthSummaryBar`** widget: KPI chips (Saudável / Atrasado / Offline / Nunca Visto + phantom devices) + `LinearProgressIndicator` for fleet active ratio. Industrial Dark palette compliance (Emerald/Amber/Rose/Zinc).
- **`VehicleHealthCard`** widget: per-vehicle card displaying plate, device ID, gap seconds, integrity score, anomaly count, and hardware status color-coded chip.
- **`fleet_health_providers.dart`**: `fleetHealthProvider` (AutoDispose AsyncNotifier) + `fleetHealthRefreshProvider` (NotifierProvider for manual refresh).
- **`FleetHealthQueryService`** interface + **`SupabaseFleetHealthQueryService`** implementation: maps RPC rows to `FleetHealthView`/`VehicleHealthEntry` VOs; `HardwareStatus` (domain) → `HardwareStatusView` (application VO) mapping.
- **`FleetHealthView`** + **`VehicleHealthEntry`**: Equatable read models in application layer. `fleetActiveRatioBps: int` (0–10,000 basis points) — replaces `double` to clear FINANCIAL-BLOCK scanner rule and match `integrityScoreBps` WS-9 convention.
- **`HardwareStatusView`** enum in `fleet_health_view.dart`: application-layer view model for hardware status (INV-13 — prevents domain import in `lib/features/`). Portuguese `.label` getters.
- **`20260902000001_fleet_health_status_rpc.sql`**: `get_fleet_health_status(uuid, int, int)` RPC with gap classification, integrity scoring, phantom device detection.
- **`20260902000002_extend_alert_type_check.sql`**: widens `valid_alert_type` CHECK to include `TELEMETRY_SILENT` (9 total types); widens `chk_alert_driver_attribution` exemption list; constraint remains intentionally NOT VALID (pre-existing rows predate driver attribution).
- **pgTAP test files** for both migrations: 9 assertions each (C/D categories), including regression guards for all 9 valid alert types.
- **`[UX] Financial Sparklines`**: `SparklineWidget` + `_SparklinePainter` (CustomPaint, no chart lib), `sparklineWindowProvider` (7d/30d toggle), `financialSparklineProvider` (FutureProvider.family), `get_financial_trend_sparkline` RPC (`20260901000005`), 11 pgTAP TCs, 5 widget tests.

### Changed

- `alerts_triade_drawer.dart` + `app_router.dart` + `app_routes.dart`: Ingestion Health Monitor wired into admin nav (modified, uncommitted).

### Fixed

- **FINANCIAL-BLOCK false positive** (`fleet_health_view.dart`): `double fleetActiveRatio` replaced by `int fleetActiveRatioBps` (bps convention). Clears scanner BLOCK without suppression.
- **CHECK widening regression** (`20260902000002`): initial draft silently dropped 4 established alert types when rebuilding `valid_alert_type` CHECK from scratch. Fixed by carrying all 9 prior types forward. Regression guards C2-C4 prevent recurrence.

### Forensic Invariants

- **INV-1**: `p_organization_id` explicit param on all new RPCs.
- **INV-2**: All RPCs SECURITY DEFINER; views `WITH (security_invoker = true)`.
- **INV-7**: `HardwareStatusView` VO eliminates `dynamic` in mapping; `fleetActiveRatioBps: int` eliminates `double` in application layer.
- **INV-13**: `features/` imports only `HardwareStatusView` (application VO), never `HardwareStatus` (domain).
- **INV-26**: RPC returns 0 rows on org mismatch (not error).

---

## [Unreleased] - Database Privilege Hardening & Forensic Trust Roots

CIA sweep (2026-06-10, merged in `88a43946` + `ea7917a4`). Closed a critical mass-deletion
vector and hardened the identity trust root behind tenant isolation.

### Security
- **Critical — mass-deletion vector closed:** Revoked `TRUNCATE` from `anon`/`authenticated`
  on all `public` tables. RLS does **not** gate `TRUNCATE`, so the legacy `ALTER DEFAULT
  PRIVILEGES` grant let an extracted anon key (or any tenant user) wipe every tenant's data
  and the immutable forensic ledger. (`20260811000000`)
- **Append-only ledger enforced at the grant layer (INV-3):** Revoked `UPDATE`/`DELETE`/
  `TRUNCATE` from client roles on `sla_audit_ledger_v2` (+ partitions) and
  `forensic_evidence_snapshots`. Client roles keep only `SELECT`/`INSERT`. (`20260811000000`)
- **Identity trust-root hardened (INV-1, INV-22):** Revoked `INSERT`/`UPDATE`/`DELETE` from
  `authenticated` on `user_roles` and `organizations` — the tables `custom_access_token_hook`
  derives the `organization_id` claim from. Removes a latent self-elevation primitive (writes
  were already RLS-blocked; the dead grant was the residual risk). Legit writes flow only
  through `SECURITY DEFINER` RPCs. `super_admin_users` already sound. (`20260811000001`)
- **anon Data API surface reduced:** Revoked all `anon` grants on 22 tenant/business tables
  (no anon RLS policy existed — defense in depth). Public-flow token tables retained.
- **search_path pinned (CWE-426):** `auto_enqueue_sanction_recommended` and
  `create_execution_for_operator` now `SET search_path = public`. (`20260811000000`)
- **PostGIS `spatial_ref_sys` write-guard:** Role-scoped `BEFORE` trigger blocks
  `anon`/`authenticated` writes on the PostGIS catalog while relocation to the `extensions`
  schema is staged (advisor `rls_disabled_in_public`). (`20260810000000`, `20260810000001`)
- **Legacy insecure default removed:** `ALTER DEFAULT PRIVILEGES` for `anon`/`authenticated`
  revoked so future tables no longer inherit the full-DML grant.

### Validated
- Forged-JWT INV-22 red-team (runtime, `SET ROLE` + `request.jwt.claims`): cross-tenant
  read/write blocked both directions, missing-claim fail-closed, anon/authenticated `TRUNCATE`
  denied, self-elevation on `user_roles` denied. JWT claim injected server-side from
  `user_roles` (client cannot influence). Residual = platform JWT signing only.
- Full test pyramid green on the merge commit: pgTAP 538, integration 82, unit/widget 1916.

### Changed
- Updated grant-baseline pgTAP tests (`20260527164000`, `20260717000008`) to assert the
  least-privilege end state (ledger append-only; `user_roles`/`organizations` SELECT-only
  for `authenticated`).

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

## [Unreleased] - URL-based Routing (go_router Migration)

### Added
- **`lib/app/routing/`**: `go_router` 17.3.0 routing layer. `app_routes.dart` (path constants + bidirectional `AdminNav`↔path map) and `app_router.dart` (`appRouterProvider`, route tree, redirect guard, `refreshListenable` on `authStateProvider`).
- URL for every screen via `StatefulShellRoute.indexedStack` (18 admin branches, 3 super-admin branches). F5 restores the current screen with auth re-validated.
- Super-admin tenant deep link `/super-admin/tenants/:id` (selects `selectedTenantIdProvider`).

### Changed
- **Major**: Replaced `MaterialApp(home:)` + imperative `Navigator` with `MaterialApp.router`. `AdminLayout` now consumes `StatefulNavigationShell` (`goBranch`); `_routeAfterAuth` uses `context.go` (async MFA decision retained in `AdminLockScreen`, not the router redirect).
- Super-admin shell converted to full branch routing wrapped in `SuperAdminSessionTimeout` + `SuperAdminGuard`; standalone MFA gate routes `/super-admin/mfa-enrollment`, `/super-admin/mfa-challenge`.
- Path URL strategy via `flutter_web_plugins` `usePathUrlStrategy()` (INV-17 safe — no `dart:html`/`dart:js`). Public token deep links (`/accept-invite`, `/review-contract`, `/justify`) preserved.

### Removed
- `adminIndexProvider` / `_AdminIndexNotifier` (in-memory nav index) and `lib/features/admin/presentation/admin_home.dart` (dissolved into router branch builders).

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
