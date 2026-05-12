/// Widget tests for [AdminLockScreen] — _isRouting navigation lock.
///
/// Validates that concurrent `_routeAfterAuth` calls are serialized via the
/// `_isRouting` guard, preventing duplicate MFA status checks and navigation
/// race conditions. INV-6 fallback (MfaChallengeScreen on error) preserved.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/super_admin/i_mfa_repository.dart';
import 'package:veraprob/domain/super_admin/mfa_status.dart';
import 'package:veraprob/features/admin/presentation/lock_screen.dart';
import 'package:veraprob/features/super_admin/presentation/screens/mfa_challenge_screen.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/mfa_providers.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart'
    hide mfaRepositoryProvider;

// ─── Mocks ──────────────────────────────────────────────────────────────────

class _MockAuthRepository extends Mock implements IAuthRepository {}

class _MockMfaRepository extends Mock implements IMfaRepository {}

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

class _FakeSecurityIncidentLogger implements SecurityIncidentLogger {
  @override
  Future<void> log({
    required String eventType,
    required Map<String, dynamic> metadata,
    required Map<String, dynamic> jwtClaimsSnapshot,
  }) async {}
}

// ─── Helpers ────────────────────────────────────────────────────────────────

String _buildSuperAdminJwt() {
  final header = base64Url
      .encode(utf8.encode('{"alg":"HS256"}'))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'app_metadata': {'super_admin': true, 'org_id': 'org-1'},
          }),
        ),
      )
      .replaceAll('=', '');
  return '$header.$payload.fake_sig';
}

AuthState _makeSuperAdminAuthState() {
  final session = _MockSession();
  final user = _MockUser();
  when(() => user.id).thenReturn('user-1');
  when(() => session.user).thenReturn(user);
  when(() => session.accessToken).thenReturn(_buildSuperAdminJwt());
  return AuthState(AuthChangeEvent.signedIn, session);
}

/// Wrapper that watches [authStateProvider] to warm it up before the
/// AdminLockScreen reads it imperatively in `_routeAfterAuth`.
class _AuthWarmupWrapper extends ConsumerWidget {
  const _AuthWarmupWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch to ensure the StreamProvider starts listening.
    ref.watch(authStateProvider);
    return const AdminLockScreen();
  }
}

Widget _buildScreen({
  required _MockAuthRepository authRepo,
  required _MockMfaRepository mfaRepo,
}) {
  final authState = _makeSuperAdminAuthState();

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      mfaRepositoryProvider.overrideWithValue(mfaRepo),
      authStateProvider.overrideWith((ref) => Stream.value(authState)),
      isSuperAdminProvider.overrideWithValue(true),
      isSuperAdminAal2Provider.overrideWithValue(true),
      securityIncidentLoggerProvider.overrideWithValue(
        _FakeSecurityIncidentLogger(),
      ),
    ],
    child: const MaterialApp(home: _AuthWarmupWrapper()),
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  late _MockAuthRepository authRepo;
  late _MockMfaRepository mfaRepo;
  late StreamController<bool> authStatusCtrl;

  setUp(() {
    authRepo = _MockAuthRepository();
    mfaRepo = _MockMfaRepository();
    authStatusCtrl = StreamController<bool>.broadcast();

    when(
      () => authRepo.authStatusStream,
    ).thenAnswer((_) => authStatusCtrl.stream);
  });

  tearDown(() {
    authStatusCtrl.close();
  });

  group('AdminLockScreen — _isRouting guard', () {
    testWidgets('duplicate auth events call getMfaStatus only once', (
      tester,
    ) async {
      final completer = Completer<MfaStatus>();
      when(() => mfaRepo.getMfaStatus()).thenAnswer((_) => completer.future);

      await tester.pumpWidget(
        _buildScreen(authRepo: authRepo, mfaRepo: mfaRepo),
      );
      // Let StreamProvider process Stream.value emission (warmup).
      await tester.pump();

      // Emit two rapid auth events — only the first should trigger routing.
      authStatusCtrl.add(true);
      await tester.pump();
      authStatusCtrl.add(true);
      await tester.pump();

      // Complete the MFA check.
      completer.complete(
        const MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      verify(() => mfaRepo.getMfaStatus()).called(1);
    });

    testWidgets('routing indicator visible during MFA check', (tester) async {
      final completer = Completer<MfaStatus>();
      when(() => mfaRepo.getMfaStatus()).thenAnswer((_) => completer.future);

      await tester.pumpWidget(
        _buildScreen(authRepo: authRepo, mfaRepo: mfaRepo),
      );
      await tester.pump();

      // Trigger routing via stream.
      authStatusCtrl.add(true);
      await tester.pump();
      // Advance past the AnimatedOpacity duration.
      await tester.pump(const Duration(milliseconds: 250));

      // The routing overlay should have opacity 1.0.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(
        const MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: true,
        ),
      );
      await tester.pump();
      await tester.pump();
    });

    testWidgets('INV-6 fallback: getMfaStatus error → MfaChallengeScreen', (
      tester,
    ) async {
      when(
        () => mfaRepo.getMfaStatus(),
      ).thenAnswer((_) async => throw Exception('network'));

      await tester.pumpWidget(
        _buildScreen(authRepo: authRepo, mfaRepo: mfaRepo),
      );
      await tester.pump();

      authStatusCtrl.add(true);
      await tester.pump();
      await tester.pump();

      // Verify the safe fallback: on MFA error, navigate to challenge screen.
      verify(() => mfaRepo.getMfaStatus()).called(greaterThanOrEqualTo(1));
      expect(find.byType(MfaChallengeScreen), findsOneWidget);
    });

    testWidgets('guard resets after navigation completes', (tester) async {
      var callCount = 0;
      when(() => mfaRepo.getMfaStatus()).thenAnswer((_) async {
        callCount++;
        return const MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: true,
        );
      });

      await tester.pumpWidget(
        _buildScreen(authRepo: authRepo, mfaRepo: mfaRepo),
      );
      await tester.pump();

      // First event triggers routing and navigates away.
      authStatusCtrl.add(true);
      await tester.pump();
      await tester.pump();

      // After navigation, the widget is replaced — guard was reset in finally.
      expect(callCount, 1);
    });
  });
}
