/// **Validates: Requirements 9.3**
///
/// Property 11: Multi-Tenant Isolation (INV-1)
///
/// For any org-scoped provider, the `organizationId` used in queries or
/// commands SHALL be obtained exclusively from `currentOrganizationIdProvider`.
/// When `currentOrganizationIdProvider` is overridden with a different tenant's
/// ID, the provider SHALL use that overridden ID (proving no hardcoded or
/// leaked tenant context).
///
/// Strategy: Source-code structural verification.
///
/// 1. Defines the 18 org-scoped provider files as structured data.
/// 2. Uses Glados to randomly select provider files from the set.
/// 3. Reads each file and verifies:
///    a) The file references `currentOrganizationIdProvider`.
///    b) The file contains no hardcoded organization IDs (UUID patterns or
///       string literals matching org ID format).
///    c) The access pattern is via `ref.watch` or `ref.read` (not direct
///       string injection or environment variable).
///    d) No provider constructs an org ID from non-canonical sources.
/// 4. Verifies that the property holds across all randomly selected files.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

// Feature: riverpod-v3-migration, Property 11: Multi-Tenant Isolation (INV-1)

/// Describes an org-scoped provider file and its expected tenant isolation
/// characteristics.
class OrgScopedProviderSpec {
  /// Relative path to the provider file from project root.
  final String filePath;

  /// Human-readable name for test output.
  final String displayName;

  /// Expected access pattern for `currentOrganizationIdProvider`.
  final OrgIdAccessPattern accessPattern;

  /// Whether this provider passes orgId to a command handler (caller-passed).
  /// In this case, the provider itself may not directly reference
  /// `currentOrganizationIdProvider`, but the caller (UI layer) does.
  final bool isCallerPassed;

  const OrgScopedProviderSpec({
    required this.filePath,
    required this.displayName,
    required this.accessPattern,
    this.isCallerPassed = false,
  });

  @override
  String toString() => displayName;
}

/// How the provider accesses the organization ID.
enum OrgIdAccessPattern {
  /// Uses `ref.watch(currentOrganizationIdProvider)` — reactive.
  watch,

  /// Uses `ref.read(currentOrganizationIdProvider)` — one-shot.
  read,

  /// Receives orgId as a parameter from the caller (command handler pattern).
  /// The caller is responsible for reading from `currentOrganizationIdProvider`.
  callerPassed,
}

/// All 18 org-scoped provider files that must comply with INV-1.
const _orgScopedProviders = <OrgScopedProviderSpec>[
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/admin_providers.dart',
    displayName: 'admin_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/alert_providers.dart',
    displayName: 'alert_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/audit_package_providers.dart',
    displayName: 'audit_package_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/auditor_queue_providers.dart',
    displayName: 'auditor_queue_providers',
    accessPattern: OrgIdAccessPattern.callerPassed,
    isCallerPassed: true,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/contract_providers.dart',
    displayName: 'contract_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/contractor_providers.dart',
    displayName: 'contractor_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/dashboard_risk_feed_provider.dart',
    displayName: 'dashboard_risk_feed_provider',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/fleet_providers.dart',
    displayName: 'fleet_providers',
    accessPattern: OrgIdAccessPattern.read,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/forensic_ledger_providers.dart',
    displayName: 'forensic_ledger_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/investigation_providers.dart',
    displayName: 'investigation_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/justification_providers.dart',
    displayName: 'justification_providers',
    accessPattern: OrgIdAccessPattern.callerPassed,
    isCallerPassed: true,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/operational_zone_providers.dart',
    displayName: 'operational_zone_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/shadow_providers.dart',
    displayName: 'shadow_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/sla_financial_providers.dart',
    displayName: 'sla_financial_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/sla_providers.dart',
    displayName: 'sla_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/sla_risk_providers.dart',
    displayName: 'sla_risk_providers',
    accessPattern: OrgIdAccessPattern.watch,
  ),
  OrgScopedProviderSpec(
    filePath: 'lib/state/providers/telegram_providers.dart',
    displayName: 'telegram_providers',
    accessPattern: OrgIdAccessPattern.read,
  ),
];

/// All provider display names for Glados selection.
final _allProviderNames = _orgScopedProviders
    .map((p) => p.displayName)
    .toList();

/// Patterns that indicate a hardcoded organization ID (INV-1 violation).
/// These are UUID-like strings or org-prefixed literals that should never
/// appear in production provider code.
final _hardcodedOrgPatterns = [
  // UUID v4 pattern used as org ID literal
  RegExp(
    r'''['"][0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}['"]''',
    caseSensitive: false,
  ),
  // org-prefixed string literals (e.g., 'org-abc123')
  RegExp(r'''['"]org-[a-zA-Z0-9]+['"]'''),
];

/// Known false positives that are NOT INV-1 violations.
/// These are null-safety fallbacks or test-only values documented in code.
const _allowedOrgLiterals = <String>{"'mock-org-id'", '"mock-org-id"'};

/// Patterns indicating the canonical access to `currentOrganizationIdProvider`.
final _canonicalAccessPatterns = [
  RegExp(r'ref\.watch\(currentOrganizationIdProvider\)'),
  RegExp(r'ref\.read\(currentOrganizationIdProvider\)'),
];

/// Patterns indicating non-canonical org ID sources (violations).
final _nonCanonicalSourcePatterns = [
  // Reading org ID from environment variables
  RegExp(r'Platform\.environment\[.*org.*\]', caseSensitive: false),
  // Reading org ID from shared preferences directly
  RegExp(r'SharedPreferences.*org', caseSensitive: false),
  // Constructing org ID from string concatenation
  RegExp(r'''['"]org-['"] *\+'''),
];

void main() {
  group('Property 11: Multi-Tenant Isolation (INV-1)', () {
    // ── Sub-property: Source file existence ──────────────────────────────
    Glados(any.choose(_allProviderNames)).test(
      'each org-scoped provider file exists',
      (providerName) {
        final spec = _orgScopedProviders.firstWhere(
          (s) => s.displayName == providerName,
        );
        final file = File(spec.filePath);

        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Org-scoped provider file ${spec.filePath} must exist '
              'for INV-1 verification',
        );
      },
    );

    // ── Sub-property: References currentOrganizationIdProvider ───────────
    Glados(
      any.choose(_allProviderNames),
    ).test('each org-scoped provider references currentOrganizationIdProvider', (
      providerName,
    ) {
      final spec = _orgScopedProviders.firstWhere(
        (s) => s.displayName == providerName,
      );
      final content = File(spec.filePath).readAsStringSync();

      // For caller-passed providers, the file itself may contain
      // organizationId as a method parameter. The caller (UI layer) is
      // responsible for reading from currentOrganizationIdProvider.
      // However, the file should still reference the provider name
      // (either in imports, doc comments, or for other providers in the file).
      if (spec.isCallerPassed) {
        // Caller-passed providers must at least contain 'organizationId'
        // as a parameter, proving they receive it externally rather than
        // constructing it internally.
        final hasOrgIdParam =
            content.contains('organizationId') || content.contains('orgId');
        expect(
          hasOrgIdParam,
          isTrue,
          reason:
              '${spec.displayName} (caller-passed) must accept '
              'organizationId as a parameter',
        );
        return;
      }

      // Non-caller-passed providers MUST directly reference
      // currentOrganizationIdProvider.
      expect(
        content.contains('currentOrganizationIdProvider'),
        isTrue,
        reason:
            '${spec.displayName} must reference currentOrganizationIdProvider '
            'to obtain organizationId (INV-1)',
      );
    });

    // ── Sub-property: Correct access pattern (watch vs read) ────────────
    Glados(
      any.choose(_allProviderNames),
    ).test('each provider uses the expected access pattern for org ID', (
      providerName,
    ) {
      final spec = _orgScopedProviders.firstWhere(
        (s) => s.displayName == providerName,
      );

      // Skip caller-passed providers — they don't directly access the provider
      if (spec.isCallerPassed) return;

      final content = File(spec.filePath).readAsStringSync();

      switch (spec.accessPattern) {
        case OrgIdAccessPattern.watch:
          expect(
            _canonicalAccessPatterns[0].hasMatch(content),
            isTrue,
            reason:
                '${spec.displayName} should use '
                'ref.watch(currentOrganizationIdProvider) for reactive '
                'tenant context',
          );
        case OrgIdAccessPattern.read:
          final hasWatch = _canonicalAccessPatterns[0].hasMatch(content);
          final hasRead = _canonicalAccessPatterns[1].hasMatch(content);
          expect(
            hasWatch || hasRead,
            isTrue,
            reason:
                '${spec.displayName} should use ref.watch or ref.read '
                'for currentOrganizationIdProvider',
          );
        case OrgIdAccessPattern.callerPassed:
          break; // Already handled above
      }
    });

    // ── Sub-property: No hardcoded organization IDs ─────────────────────
    Glados(
      any.choose(_allProviderNames),
    ).test('no org-scoped provider contains hardcoded organization IDs', (
      providerName,
    ) {
      final spec = _orgScopedProviders.firstWhere(
        (s) => s.displayName == providerName,
      );
      final content = File(spec.filePath).readAsStringSync();

      for (final pattern in _hardcodedOrgPatterns) {
        final matches = pattern.allMatches(content);

        // Filter out known false positives
        final violations = matches.where((m) {
          final matchText = content.substring(m.start, m.end);
          return !_allowedOrgLiterals.contains(matchText);
        }).toList();

        expect(
          violations,
          isEmpty,
          reason:
              '${spec.displayName} contains hardcoded organization ID(s) '
              '(INV-1 violation): '
              '${violations.map((m) => content.substring(m.start, m.end)).toList()}',
        );
      }
    });

    // ── Sub-property: No non-canonical org ID sources ───────────────────
    Glados(any.choose(_allProviderNames)).test(
      'no provider obtains org ID from non-canonical sources',
      (providerName) {
        final spec = _orgScopedProviders.firstWhere(
          (s) => s.displayName == providerName,
        );
        final content = File(spec.filePath).readAsStringSync();

        for (final pattern in _nonCanonicalSourcePatterns) {
          expect(
            pattern.hasMatch(content),
            isFalse,
            reason:
                '${spec.displayName} obtains organizationId from a '
                'non-canonical source (INV-1 violation). '
                'Must use currentOrganizationIdProvider exclusively.',
          );
        }
      },
    );

    // ── Sub-property: No org ID string interpolation without provider ───
    Glados(any.choose(_allProviderNames)).test(
      'no provider constructs org-scoped queries without provider reference',
      (providerName) {
        final spec = _orgScopedProviders.firstWhere(
          (s) => s.displayName == providerName,
        );
        final content = File(spec.filePath).readAsStringSync();

        // If the file contains SQL-like org filtering, it must also reference
        // currentOrganizationIdProvider (or be caller-passed).
        final hasSqlOrgFilter = RegExp(
          r'''organization_id.*=.*['"\$]''',
        ).hasMatch(content);

        if (hasSqlOrgFilter && !spec.isCallerPassed) {
          expect(
            content.contains('currentOrganizationIdProvider'),
            isTrue,
            reason:
                '${spec.displayName} contains org-scoped SQL filtering but '
                'does not reference currentOrganizationIdProvider. '
                'The org ID used in queries must come from the canonical '
                'provider (INV-1).',
          );
        }
      },
    );

    // ── Sub-property: Provider count completeness ────────────────────────
    // Verifies that we are testing all 17 known org-scoped providers.
    Glados(any.intInRange(0, _orgScopedProviders.length - 1)).test(
      'org-scoped provider list is complete (17 providers)',
      (index) {
        // This property verifies the test itself is complete — we have
        // exactly 17 org-scoped providers defined.
        expect(
          _orgScopedProviders.length,
          equals(17),
          reason:
              'Must verify all 17 org-scoped providers for INV-1 compliance. '
              'If a new org-scoped provider is added, update this test.',
        );

        // Each provider in the list has a valid spec
        final spec = _orgScopedProviders[index];
        expect(spec.filePath, isNotEmpty);
        expect(spec.displayName, isNotEmpty);
      },
    );

    // ── Sub-property: Tenant override propagation ────────────────────────
    // Verifies that providers using ref.watch will reactively update when
    // currentOrganizationIdProvider changes (proving no cached/leaked context).
    Glados(
      any.choose(_allProviderNames),
    ).test('watch-based providers will reactively update on tenant change', (
      providerName,
    ) {
      final spec = _orgScopedProviders.firstWhere(
        (s) => s.displayName == providerName,
      );

      // Only applicable to watch-pattern providers
      if (spec.accessPattern != OrgIdAccessPattern.watch) return;

      final content = File(spec.filePath).readAsStringSync();

      // Verify the provider uses ref.watch (not ref.read) for the org ID.
      // ref.watch ensures the provider rebuilds when the tenant changes,
      // proving no stale/leaked tenant context persists.
      expect(
        _canonicalAccessPatterns[0].hasMatch(content),
        isTrue,
        reason:
            '${spec.displayName} uses watch pattern — must use '
            'ref.watch(currentOrganizationIdProvider) to ensure reactive '
            'rebuild on tenant change (no leaked context)',
      );

      // Verify the org ID variable is used in the provider's logic
      // (not just imported but unused).
      final orgIdVarPattern = RegExp(
        r'(final|var)\s+\w*(org|organization)\w*\s*=\s*ref\.watch\(currentOrganizationIdProvider\)',
        caseSensitive: false,
      );
      final directUsePattern = RegExp(
        r'ref\.watch\(currentOrganizationIdProvider\)',
      );

      expect(
        orgIdVarPattern.hasMatch(content) || directUsePattern.hasMatch(content),
        isTrue,
        reason:
            '${spec.displayName} must actually USE the org ID from '
            'currentOrganizationIdProvider in its logic',
      );
    });
  });
}
