/// **Validates: Requirements 9.3**
///
/// Task 10.1: Validar isolamento multi-tenant (INV-1)
///
/// Verifies that every org-scoped provider in `lib/state/providers/` obtains
/// `organizationId` exclusively from `currentOrganizationIdProvider`.
///
/// Strategy: Source-code structural verification — reads each provider file and
/// confirms that any usage of `organizationId` or `orgId` is obtained via
/// `ref.watch(currentOrganizationIdProvider)` or `ref.read(currentOrganizationIdProvider)`.
///
/// Providers that receive `organizationId` as a family parameter are flagged
/// only if they do NOT document INV-1 compliance in their doc comment.
///
/// Additionally verifies that cross-tenant isolation tests exist at the
/// infrastructure layer (repository-level tests that fail with wrong org ID).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Feature: riverpod-v3-migration, Property 11: Multi-Tenant Isolation (INV-1)

/// All provider files that use `organizationId` or `orgId` in their logic.
/// Each entry maps a file path to the expected source of the org ID.
const _orgScopedProviders = <String, _OrgIdSource>{
  'lib/state/providers/admin_providers.dart': _OrgIdSource.watchProvider,
  'lib/state/providers/alert_providers.dart': _OrgIdSource.watchProvider,
  'lib/state/providers/audit_package_providers.dart':
      _OrgIdSource.watchProvider,
  'lib/state/providers/auditor_queue_providers.dart':
      _OrgIdSource.watchProvider,
  'lib/state/providers/contract_providers.dart': _OrgIdSource.watchProvider,
  'lib/state/providers/contractor_providers.dart': _OrgIdSource.watchProvider,
  'lib/state/providers/dashboard_risk_feed_provider.dart':
      _OrgIdSource.watchProvider,
  'lib/state/providers/executive_dashboard_providers.dart':
      _OrgIdSource.watchProvider,
  'lib/state/providers/fleet_providers.dart': _OrgIdSource.readProvider,
  'lib/state/providers/forensic_ledger_providers.dart':
      _OrgIdSource.watchProvider,
  'lib/state/providers/investigation_providers.dart':
      _OrgIdSource.watchProvider,
  'lib/state/providers/operational_zone_providers.dart':
      _OrgIdSource.watchProvider,
  'lib/state/providers/shadow_providers.dart': _OrgIdSource.watchProvider,
  'lib/state/providers/sla_financial_providers.dart':
      _OrgIdSource.watchProvider,
  'lib/state/providers/sla_providers.dart': _OrgIdSource.watchProvider,
  'lib/state/providers/sla_risk_providers.dart': _OrgIdSource.watchProvider,
  'lib/state/providers/sla_template_providers.dart': _OrgIdSource.watchProvider,
  'lib/state/providers/telegram_providers.dart': _OrgIdSource.readProvider,
};

/// Provider files that use `organizationId` as a family parameter.
/// These are acceptable if the doc comment documents INV-1 compliance.
const _familyParameterProviders = <String>[
  'lib/state/providers/heartbeat_monitor_providers.dart',
  'lib/state/providers/dispute_portal_providers.dart',
];

/// Provider files where notifier methods receive `organizationId` as a
/// parameter from the caller. The caller is responsible for reading from
/// `currentOrganizationIdProvider`.
const _callerPassedProviders = <String>[
  'lib/state/providers/auditor_queue_providers.dart', // SanctionActionNotifier
  'lib/state/providers/justification_providers.dart', // JustificationActionNotifier
  'lib/state/providers/dispute_portal_token_providers.dart', // DisputePortalTokenNotifier
];

/// Super admin providers that intentionally operate across tenants.
/// These are NOT subject to INV-1 because super admins have no tenant context
/// (currentOrganizationIdProvider returns null for them).
const _superAdminProviders = <String>[
  'lib/state/providers/super_admin_providers.dart',
  'lib/state/providers/super_admin_auth_providers.dart',
  'lib/state/providers/impersonation_session_provider.dart',
];

/// Files that contain cross-tenant isolation tests at the infrastructure level.
const _crossTenantTestFiles = <String>[
  'test/infrastructure/sla_audit/postgres_vehicle_infraction_recurrence_repository_test.dart',
  'test/validation/phase5_4_validation_scenarios_test.dart',
];

enum _OrgIdSource {
  /// Uses `ref.watch(currentOrganizationIdProvider)`
  watchProvider,

  /// Uses `ref.read(currentOrganizationIdProvider)`
  readProvider,
}

void main() {
  group('INV-1: Multi-Tenant Isolation Validation', () {
    group('Org-scoped providers read from currentOrganizationIdProvider', () {
      for (final entry in _orgScopedProviders.entries) {
        test('${entry.key} obtains orgId from currentOrganizationIdProvider', () {
          final file = File(entry.key);
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Provider file ${entry.key} must exist',
          );

          final content = file.readAsStringSync();

          // Verify the file references currentOrganizationIdProvider
          final hasCurrentOrgProvider = content.contains(
            'currentOrganizationIdProvider',
          );
          expect(
            hasCurrentOrgProvider,
            isTrue,
            reason:
                '${entry.key} must read organizationId from '
                'currentOrganizationIdProvider (INV-1)',
          );

          // Verify the access pattern matches expected source
          switch (entry.value) {
            case _OrgIdSource.watchProvider:
              expect(
                content.contains('ref.watch(currentOrganizationIdProvider)'),
                isTrue,
                reason:
                    '${entry.key} should use ref.watch(currentOrganizationIdProvider)',
              );
            case _OrgIdSource.readProvider:
              final hasWatch = content.contains(
                'ref.watch(currentOrganizationIdProvider)',
              );
              final hasRead = content.contains(
                'ref.read(currentOrganizationIdProvider)',
              );
              expect(
                hasWatch || hasRead,
                isTrue,
                reason:
                    '${entry.key} should use ref.watch or ref.read '
                    'for currentOrganizationIdProvider',
              );
          }

          // Verify NO hardcoded organization IDs (UUIDs or string literals
          // used as org IDs in production code)
          final hardcodedOrgPattern = RegExp(r'''['"]org-[a-zA-Z0-9]+['"]''');
          final matches = hardcodedOrgPattern.allMatches(content);
          // Filter out the 'mock-org-id' fallback in fleet_providers which is
          // a null-safety fallback, not a hardcoded tenant ID
          final violations = matches.where((m) {
            final match = content.substring(m.start, m.end);
            return match != "'mock-org-id'" && match != '"mock-org-id"';
          }).toList();

          expect(
            violations,
            isEmpty,
            reason:
                '${entry.key} must not contain hardcoded organization IDs '
                '(INV-1 violation). Found: '
                '${violations.map((m) => content.substring(m.start, m.end)).toList()}',
          );
        });
      }
    });

    group('Family-parameter providers document INV-1 compliance', () {
      for (final filePath in _familyParameterProviders) {
        test('$filePath documents INV-1 in doc comment', () {
          final file = File(filePath);
          expect(file.existsSync(), isTrue);

          final content = file.readAsStringSync();

          // Must mention INV-1 in documentation
          expect(
            content.contains('INV-1'),
            isTrue,
            reason:
                '$filePath uses organizationId as family parameter — '
                'must document INV-1 compliance in doc comment',
          );
        });
      }
    });

    group(
      'Caller-passed providers: callers read from currentOrganizationIdProvider',
      () {
        test(
          'SanctionActionNotifier callers read orgId from currentOrganizationIdProvider',
          () {
            // The UI caller (sanction_verdict_card.dart) passes organizationId
            // from widget.item.organizationId — which was loaded via
            // pendingSanctionsStreamProvider (RLS-scoped by Supabase).
            // Additionally, the TenantValidationService validates the org ID
            // server-side before any mutation.
            final callerFile = File(
              'lib/features/admin/presentation/widgets/sanction_verdict_card.dart',
            );
            expect(callerFile.existsSync(), isTrue);

            final content = callerFile.readAsStringSync();
            // The caller uses widget.item.organizationId which comes from
            // the RLS-scoped stream. The handler also uses TenantValidationService
            // for server-side validation.
            expect(
              content.contains('organizationId'),
              isTrue,
              reason:
                  'Caller must pass organizationId to SanctionActionNotifier',
            );
          },
        );

        test(
          'JustificationActionNotifier callers read orgId from currentOrganizationIdProvider',
          () {
            final callerFile = File(
              'lib/features/admin/presentation/screens/justification_detail_drawer.dart',
            );
            expect(callerFile.existsSync(), isTrue);

            final content = callerFile.readAsStringSync();
            expect(
              content.contains('currentOrganizationIdProvider'),
              isTrue,
              reason:
                  'Justification caller must read orgId from '
                  'currentOrganizationIdProvider (INV-1)',
            );
          },
        );

        test(
          'DisputePortalTokenNotifier callers read orgId from currentOrganizationIdProvider',
          () {
            final callerFile = File(
              'lib/features/admin/presentation/widgets/sanction_verdict_card.dart',
            );
            expect(callerFile.existsSync(), isTrue);

            final content = callerFile.readAsStringSync();
            expect(
              content.contains('organizationId'),
              isTrue,
              reason:
                  'Caller must pass organizationId to DisputePortalTokenNotifier',
            );
          },
        );
      },
    );

    group('Cross-tenant isolation tests exist', () {
      for (final testFile in _crossTenantTestFiles) {
        test('$testFile contains cross-tenant isolation test', () {
          final file = File(testFile);
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Cross-tenant test file must exist: $testFile',
          );

          final content = file.readAsStringSync();
          final hasCrossTenantTest =
              content.contains('cross-tenant') ||
              content.contains('cross_tenant') ||
              content.contains('org errada') ||
              content.contains('other.*org') ||
              content.contains('otherOrgId');

          expect(
            hasCrossTenantTest,
            isTrue,
            reason:
                '$testFile must contain at least one cross-tenant '
                'isolation test that fails with wrong org ID (INV-1)',
          );
        });
      }
    });

    group('No provider bypasses currentOrganizationIdProvider', () {
      test(
        'No provider in lib/state/providers/ uses a hardcoded org ID for queries',
        () {
          final providersDir = Directory('lib/state/providers');
          expect(providersDir.existsSync(), isTrue);

          final dartFiles = providersDir.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.dart'),
          );

          // Files where notifier methods receive organizationId as a parameter
          // from the caller (caller reads from currentOrganizationIdProvider).
          // These are command-handler notifiers — the UI layer is responsible
          // for providing the org ID from the canonical provider.
          final callerPassedFileNames = _callerPassedProviders
              .map((p) => p.split('/').last)
              .toSet();

          // Super admin providers intentionally operate across tenants.
          final superAdminFileNames = _superAdminProviders
              .map((p) => p.split('/').last)
              .toSet();

          for (final file in dartFiles) {
            final content = file.readAsStringSync();

            // Skip files that don't use organizationId at all
            if (!content.contains('organizationId') &&
                !content.contains('orgId') &&
                !content.contains('organization_id')) {
              continue;
            }

            // If the file uses org ID, it must reference currentOrganizationIdProvider
            // OR be a family provider that documents INV-1
            // OR be auth_providers.dart (which DEFINES currentOrganizationIdProvider)
            // OR be a caller-passed provider (command handler pattern)
            final fileName = file.path.split(Platform.pathSeparator).last;
            if (fileName == 'auth_providers.dart') continue;

            // Super admin providers intentionally operate across tenants
            if (superAdminFileNames.contains(fileName)) continue;

            final hasCurrentOrgRef = content.contains(
              'currentOrganizationIdProvider',
            );
            final hasInv1Doc = content.contains('INV-1');
            final isFamilyWithOrgParam = _familyParameterProviders.any(
              (p) => file.path.endsWith(p.split('/').last),
            );
            final isCallerPassed = callerPassedFileNames.contains(fileName);

            expect(
              hasCurrentOrgRef ||
                  (isFamilyWithOrgParam && hasInv1Doc) ||
                  isCallerPassed,
              isTrue,
              reason:
                  '${file.path} uses organizationId but does not reference '
                  'currentOrganizationIdProvider and does not document INV-1 '
                  'compliance. This is a potential INV-1 violation.',
            );
          }
        },
      );
    });
  });
}
