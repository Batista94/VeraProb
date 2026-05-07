// ignore_for_file: avoid_redundant_argument_values
/// Property-based tests for [SuperAdminGuard] Zero-Trust security.
///
/// Uses glados-style iteration (100+ inputs per property) to verify
/// that the guard's access control, logging, impersonation validation,
/// and session expiration behave correctly across all input combinations.
///
/// **INV-30:** Tests override providers — no direct Supabase client access.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/features/super_admin/application/start_impersonation_handler.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/not_found_page.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/super_admin_guard.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/impersonation_session_provider.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';

// ─── Mocks & Fakes ──────────────────────────────────────────────────────────

class MockSession extends Mock implements Session {}

class MockUser extends Mock implements User {}

/// Stub [IDateTimeProvider] that returns a fixed UTC time.
class _FixedDateTimeProvider implements IDateTimeProvider {
  final DateTime _now;
  _FixedDateTimeProvider(this._now);

  @override
  DateTime nowUtc() => _now;

  @override
  DateTime nowBrazil() => _now;
}

/// Tracks calls to [SecurityIncidentLogger.log].
class _FakeSecurityIncidentLogger implements SecurityIncidentLogger {
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<void> log({
    required String eventType,
    required Map<String, dynamic> metadata,
    required Map<String, dynamic> jwtClaimsSnapshot,
  }) async {
    calls.add({
      'event_type': eventType,
      'metadata': metadata,
      'jwt_claims_snapshot': jwtClaimsSnapshot,
    });
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Generates a deterministic UUID-like string from an integer seed.
String _uuidFromSeed(int seed) {
  final hex = seed.abs().toRadixString(16).padLeft(32, '0').substring(0, 32);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '4${hex.substring(13, 16)}-a${hex.substring(17, 20)}-'
      '${hex.substring(20, 32)}';
}

/// Creates a [StreamProvider] override that emits an [AuthState] with
/// a mock session whose user has the given [userId].
Override _authStateWithUserId(String userId) {
  final mockUser = MockUser();
  when(() => mockUser.id).thenReturn(userId);

  final mockSession = MockSession();
  when(() => mockSession.user).thenReturn(mockUser);
  when(() => mockSession.accessToken).thenReturn('fake.jwt.token');

  final authState = AuthState(AuthChangeEvent.signedIn, mockSession);

  return authStateProvider.overrideWith((ref) => Stream.value(authState));
}

/// Builds the guard under test with the given provider overrides.
Widget _buildGuard({
  required bool isSuperAdmin,
  required bool isAal2,
  ImpersonationSessionInfo? impersonationSession,
  _FakeSecurityIncidentLogger? logger,
  Override? authOverride,
}) {
  final fakeLogger = logger ?? _FakeSecurityIncidentLogger();

  return ProviderScope(
    overrides: [
      isSuperAdminProvider.overrideWithValue(isSuperAdmin),
      isSuperAdminAal2Provider.overrideWithValue(isAal2),
      activeImpersonationSessionProvider.overrideWith(
        (ref) => impersonationSession,
      ),
      securityIncidentLoggerProvider.overrideWithValue(fakeLogger),
      authOverride ??
          authStateProvider.overrideWith(
            (ref) => const Stream<AuthState>.empty(),
          ),
    ],
    child: const MaterialApp(
      home: SuperAdminGuard(child: Scaffold(body: Text('CHILD_RENDERED'))),
    ),
  );
}

// ─── PBT Tests ──────────────────────────────────────────────────────────────

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  final now = DateTime.utc(2025, 7, 15, 12, 0, 0);
  final dateTimeProvider = _FixedDateTimeProvider(now);

  // ════════════════════════════════════════════════════════════════════════
  // Property 1: Controle de acesso do Guard
  // Feature: superadmin-zero-trust-security, Property 1
  // **Validates: Requirements 1.1, 1.2, 6.1**
  //
  // For ANY JWT state (with/without super_admin, with/without aal2),
  // child is rendered iff super_admin == true AND aal2 == true.
  // ════════════════════════════════════════════════════════════════════════
  group('Feature: superadmin-zero-trust-security, '
      'Property 1: Controle de acesso do Guard', () {
    // Generate 120 combinations covering all 4 boolean states.
    for (var i = 0; i < 120; i++) {
      final isSuperAdmin = i % 2 == 0;
      final isAal2 = (i ~/ 2) % 2 == 0;

      testWidgets('iter $i: superAdmin=$isSuperAdmin, aal2=$isAal2 → '
          '${isSuperAdmin && isAal2 ? "child" : "blocked"}', (tester) async {
        await tester.pumpWidget(
          _buildGuard(isSuperAdmin: isSuperAdmin, isAal2: isAal2),
        );
        await tester.pump();

        if (isSuperAdmin && isAal2) {
          expect(
            find.text('CHILD_RENDERED'),
            findsOneWidget,
            reason: 'Child MUST render when superAdmin=true AND aal2=true',
          );
        } else if (!isSuperAdmin) {
          expect(
            find.byType(NotFoundPage),
            findsOneWidget,
            reason: 'NotFoundPage MUST render when superAdmin=false (INV-26)',
          );
          expect(
            find.text('CHILD_RENDERED'),
            findsNothing,
            reason: 'Child MUST NOT render when superAdmin=false',
          );
        } else {
          // isSuperAdmin=true, isAal2=false → Fail-Fast (no child).
          expect(
            find.text('CHILD_RENDERED'),
            findsNothing,
            reason: 'Child MUST NOT render when aal2=false (Fail-Fast)',
          );
        }
      });
    }
  });

  // ════════════════════════════════════════════════════════════════════════
  // Property 2: Logging de incidentes em falha do Guard
  // Feature: superadmin-zero-trust-security, Property 2
  // **Validates: Requirements 1.4, 5.1**
  //
  // For ANY JWT state where super_admin != true, the guard MUST fire
  // an RPC log-security-incident with required fields.
  // ════════════════════════════════════════════════════════════════════════
  group('Feature: superadmin-zero-trust-security, '
      'Property 2: Logging de incidentes em falha do Guard', () {
    for (var i = 0; i < 110; i++) {
      final isAal2 = i % 2 == 0;

      testWidgets('iter $i: superAdmin=false, aal2=$isAal2 → '
          'RPC fired with SECURITY_VIOLATION_BYPASS_ATTEMPT', (tester) async {
        final logger = _FakeSecurityIncidentLogger();

        await tester.pumpWidget(
          _buildGuard(isSuperAdmin: false, isAal2: isAal2, logger: logger),
        );
        await tester.pump();

        // RPC must have been called.
        expect(
          logger.calls,
          isNotEmpty,
          reason: 'Security incident MUST be logged on access denial',
        );

        final call = logger.calls.first;

        // event_type must be correct.
        expect(
          call['event_type'],
          equals('SECURITY_VIOLATION_BYPASS_ATTEMPT'),
          reason: 'event_type MUST be SECURITY_VIOLATION_BYPASS_ATTEMPT',
        );

        // metadata must contain source.
        final metadata = call['metadata'] as Map<String, dynamic>;
        expect(
          metadata,
          containsPair('source', 'flutter_guard'),
          reason: 'metadata.source MUST be flutter_guard',
        );

        // jwt_claims_snapshot must be present.
        expect(
          call.containsKey('jwt_claims_snapshot'),
          isTrue,
          reason: 'jwt_claims_snapshot MUST be present',
        );
      });
    }
  });

  // ════════════════════════════════════════════════════════════════════════
  // Property 3: Continuidade do claim SuperAdmin durante personificação
  // Feature: superadmin-zero-trust-security, Property 3
  // **Validates: Requirements 2.1**
  //
  // For ANY active impersonation session, the guard MUST block access
  // when the actor (SuperAdmin) loses the super_admin claim.
  // ════════════════════════════════════════════════════════════════════════
  group(
    'Feature: superadmin-zero-trust-security, '
    'Property 3: Continuidade do claim SuperAdmin durante personificação',
    () {
      final userId = _uuidFromSeed(42);

      for (var i = 0; i < 110; i++) {
        final isSuperAdmin = i % 3 != 0; // ~67% true, ~33% false

        testWidgets(
          'iter $i: superAdmin=$isSuperAdmin with active impersonation → '
          '${isSuperAdmin ? "allowed" : "blocked"}',
          (tester) async {
            final session = ImpersonationSessionInfo(
              sessionId: 'session-$i',
              targetOrgId: 'org-target',
              targetOrgName: 'Target Org',
              impersonatorId: userId,
              issuedAt: now.subtract(const Duration(minutes: 10)),
              expiresAt: now.add(const Duration(minutes: 20)),
              dateTimeProvider: dateTimeProvider,
            );

            final logger = _FakeSecurityIncidentLogger();

            await tester.pumpWidget(
              _buildGuard(
                isSuperAdmin: isSuperAdmin,
                isAal2: true,
                impersonationSession: session,
                logger: logger,
                authOverride: _authStateWithUserId(userId),
              ),
            );
            await tester.pumpAndSettle();

            if (!isSuperAdmin) {
              // Actor lost super_admin → guard blocks (Step 1 fires first).
              expect(
                find.byType(NotFoundPage),
                findsOneWidget,
                reason:
                    'Guard MUST block when actor loses super_admin '
                    'during impersonation',
              );
              expect(find.text('CHILD_RENDERED'), findsNothing);
              expect(
                logger.calls,
                isNotEmpty,
                reason:
                    'Security incident MUST be logged when actor '
                    'loses super_admin',
              );
            } else {
              // Actor retains super_admin + matching ID → child rendered.
              expect(
                find.text('CHILD_RENDERED'),
                findsOneWidget,
                reason:
                    'Guard MUST allow when actor retains super_admin '
                    'during impersonation',
              );
            }
          },
        );
      }
    },
  );

  // ════════════════════════════════════════════════════════════════════════
  // Property 4: Expiração de sessão de personificação
  // Feature: superadmin-zero-trust-security, Property 4
  // **Validates: Requirements 2.2**
  //
  // For ANY impersonation session with expires_at in the past,
  // the guard MUST redirect (not render child).
  // ════════════════════════════════════════════════════════════════════════
  group('Feature: superadmin-zero-trust-security, '
      'Property 4: Expiração de sessão de personificação', () {
    final userId = _uuidFromSeed(42);

    for (var i = 0; i < 110; i++) {
      final isExpired = i % 2 == 0;
      final offset = Duration(minutes: i + 1);
      final expiresAt = isExpired ? now.subtract(offset) : now.add(offset);

      testWidgets('iter $i: expires_at=${isExpired ? "past" : "future"} → '
          '${isExpired ? "redirect" : "child"}', (tester) async {
        final session = ImpersonationSessionInfo(
          sessionId: 'session-$i',
          targetOrgId: 'org-target',
          targetOrgName: 'Target Org',
          impersonatorId: userId,
          issuedAt: now.subtract(const Duration(minutes: 30)),
          expiresAt: expiresAt,
          dateTimeProvider: dateTimeProvider,
        );

        await tester.pumpWidget(
          _buildGuard(
            isSuperAdmin: true,
            isAal2: true,
            impersonationSession: session,
            authOverride: _authStateWithUserId(userId),
          ),
        );
        await tester.pump();

        if (isExpired) {
          // Expired → child MUST NOT render (redirect triggered).
          expect(
            find.text('CHILD_RENDERED'),
            findsNothing,
            reason:
                'Expired impersonation MUST trigger redirect, '
                'not render child',
          );
        } else {
          // Valid → child rendered.
          expect(
            find.text('CHILD_RENDERED'),
            findsOneWidget,
            reason:
                'Valid impersonation session MUST allow child '
                'rendering',
          );
        }
      });
    }
  });

  // ════════════════════════════════════════════════════════════════════════
  // Property 5: Detecção de mismatch de Actor_ID
  // Feature: superadmin-zero-trust-security, Property 5
  // **Validates: Requirements 2.3**
  //
  // For ANY pair of UUIDs where impersonator_user_id != JWT userId,
  // the guard MUST terminate the session and log the incident.
  // ════════════════════════════════════════════════════════════════════════
  group('Feature: superadmin-zero-trust-security, '
      'Property 5: Detecção de mismatch de Actor_ID', () {
    for (var i = 0; i < 110; i++) {
      final impersonatorId = _uuidFromSeed(i * 2);
      final currentUserId = _uuidFromSeed(i * 2 + 1);

      testWidgets('iter $i: impersonator=$impersonatorId vs '
          'current=$currentUserId → terminate + log', (tester) async {
        // Sanity: seeds must produce different UUIDs.
        expect(impersonatorId, isNot(equals(currentUserId)));

        final session = ImpersonationSessionInfo(
          sessionId: 'session-$i',
          targetOrgId: 'org-target',
          targetOrgName: 'Target Org',
          impersonatorId: impersonatorId,
          issuedAt: now.subtract(const Duration(minutes: 10)),
          expiresAt: now.add(const Duration(minutes: 20)),
          dateTimeProvider: dateTimeProvider,
        );

        final logger = _FakeSecurityIncidentLogger();

        await tester.pumpWidget(
          _buildGuard(
            isSuperAdmin: true,
            isAal2: true,
            impersonationSession: session,
            logger: logger,
            authOverride: _authStateWithUserId(currentUserId),
          ),
        );
        await tester.pump();

        // Mismatch → NotFoundPage MUST be rendered.
        expect(
          find.byType(NotFoundPage),
          findsOneWidget,
          reason: 'Actor_ID mismatch MUST render NotFoundPage',
        );
        expect(
          find.text('CHILD_RENDERED'),
          findsNothing,
          reason: 'Child MUST NOT render on Actor_ID mismatch',
        );

        // Security incident MUST be logged.
        expect(
          logger.calls,
          isNotEmpty,
          reason:
              'Security incident MUST be logged on Actor_ID '
              'mismatch',
        );
        expect(
          logger.calls.first['event_type'],
          equals('SECURITY_VIOLATION_IMPERSONATION_MISMATCH'),
          reason:
              'event_type MUST be '
              'SECURITY_VIOLATION_IMPERSONATION_MISMATCH',
        );
      });
    }
  });
}
