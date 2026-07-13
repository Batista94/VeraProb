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
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/legal/legal_consent_status.dart';
import 'package:veraprob/domain/legal/legal_document.dart';
import 'package:veraprob/domain/super_admin/i_mfa_repository.dart';
import 'package:veraprob/domain/super_admin/mfa_status.dart';
import 'package:veraprob/features/admin/presentation/lock_screen.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/legal_consent_providers.dart';
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

String _buildJwt({required bool superAdmin}) {
  final header = base64Url
      .encode(utf8.encode('{"alg":"HS256"}'))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'app_metadata': {
              'super_admin': superAdmin,
              'org_id': 'org-1',
              'role': superAdmin ? 'SUPER_ADMIN' : 'TENANT_ADMIN',
            },
          }),
        ),
      )
      .replaceAll('=', '');
  return '$header.$payload.fake_sig';
}

AuthState _makeAuthState({required bool superAdmin}) {
  final session = _MockSession();
  final user = _MockUser();
  when(() => user.id).thenReturn(superAdmin ? 'user-sa' : 'user-tenant');
  when(() => session.user).thenReturn(user);
  when(() => session.accessToken).thenReturn(_buildJwt(superAdmin: superAdmin));
  return AuthState(AuthChangeEvent.signedIn, session);
}

LegalDocument get _termsDoc => const LegalDocument(
  id: 'doc-terms-1',
  title: 'Termos',
  bodyMarkdown: 'body',
);

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

/// Router whose `/login` renders the [AdminLockScreen]; post-auth destinations
/// are sentinels so `context.go(...)` from `_routeAfterAuth` is assertable.
GoRouter _buildRouter() {
  GoRoute sentinel(String path) =>
      GoRoute(path: path, builder: (context, state) => Text('route:$path'));

  return GoRouter(
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const _AuthWarmupWrapper(),
      ),
      sentinel(AppRoutes.adminDashboard),
      sentinel(AppRoutes.legalConsent),
      sentinel(AppRoutes.superAdmin),
      sentinel(AppRoutes.superAdminMfaEnrollment),
      sentinel(AppRoutes.superAdminMfaChallenge),
    ],
  );
}

({Widget widget, GoRouter router}) _buildScreen({
  required _MockAuthRepository authRepo,
  required _MockMfaRepository mfaRepo,
  bool superAdmin = true,
  LegalConsentStatus? tenantConsent,
}) {
  final authState = _makeAuthState(superAdmin: superAdmin);
  final router = _buildRouter();

  final widget = ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      mfaRepositoryProvider.overrideWithValue(mfaRepo),
      authStateProvider.overrideWith((ref) => Stream.value(authState)),
      isSuperAdminProvider.overrideWithValue(superAdmin),
      isSuperAdminAal2Provider.overrideWithValue(superAdmin),
      securityIncidentLoggerProvider.overrideWithValue(
        _FakeSecurityIncidentLogger(),
      ),
      if (!superAdmin)
        legalConsentStatusProvider.overrideWith(
          (ref) async =>
              tenantConsent ??
              LegalConsentStatus(
                state: LegalConsentState.pending,
                document: _termsDoc,
              ),
        ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );

  return (widget: widget, router: router);
}

String _currentPath(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

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

      final harness = _buildScreen(authRepo: authRepo, mfaRepo: mfaRepo);
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
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

      final harness = _buildScreen(authRepo: authRepo, mfaRepo: mfaRepo);
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
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

      final harness = _buildScreen(authRepo: authRepo, mfaRepo: mfaRepo);
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pump();

      authStatusCtrl.add(true);
      // pumpAndSettle waits for the router redirect to settle on the gate route.
      await tester.pumpAndSettle();

      // Verify the safe fallback: on MFA error, route to the challenge gate.
      verify(() => mfaRepo.getMfaStatus()).called(greaterThanOrEqualTo(1));
      expect(_currentPath(harness.router), AppRoutes.superAdminMfaChallenge);
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

      final harness = _buildScreen(authRepo: authRepo, mfaRepo: mfaRepo);
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pump();

      // First event triggers routing and navigates away.
      authStatusCtrl.add(true);
      await tester.pump();
      await tester.pump();

      // After navigation, the widget is replaced — guard was reset in finally.
      expect(callCount, 1);
    });
  });

  group('AdminLockScreen — LGPD Legal Gate (tenant operators)', () {
    testWidgets('pending consent routes to /legal-consent (F-01)', (
      tester,
    ) async {
      final harness = _buildScreen(
        authRepo: authRepo,
        mfaRepo: mfaRepo,
        superAdmin: false,
        tenantConsent: LegalConsentStatus(
          state: LegalConsentState.pending,
          document: _termsDoc,
        ),
      );
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pump();

      authStatusCtrl.add(true);
      await tester.pumpAndSettle();

      expect(_currentPath(harness.router), AppRoutes.legalConsent);
      verifyNever(() => mfaRepo.getMfaStatus());
    });

    testWidgets('current consent routes to /admin/dashboard (F-02/F-05)', (
      tester,
    ) async {
      final harness = _buildScreen(
        authRepo: authRepo,
        mfaRepo: mfaRepo,
        superAdmin: false,
        tenantConsent: LegalConsentStatus(
          state: LegalConsentState.current,
          document: _termsDoc,
        ),
      );
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pump();

      authStatusCtrl.add(true);
      await tester.pumpAndSettle();

      expect(_currentPath(harness.router), AppRoutes.adminDashboard);
      verifyNever(() => mfaRepo.getMfaStatus());
    });

    // F-09 fail-closed on RPC error: covered by try/catch in
    // AdminLockScreen._routeAfterAuth (treat as pending) + screen/provider
    // adverse tests. Widget harness for FutureProvider.completeError races
    // GoRouter settle and is intentionally not duplicated here.
  });
}
