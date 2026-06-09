/// Widget tests for [MfaChallengeScreen] — CT30 happy path + lockout
/// adversarial scenarios (INV-6, INV-22).
///
/// Strategy: override [mfaChallengeHandlerProvider] with a mocktail mock and
/// drive the screen via `tester.enterText` (auto-submits at length 6). Post-auth
/// navigation now flows through [GoRouter] (`context.go`), so the harness mounts
/// the screen at `/mfa` with sentinel routes for the Tenants branch and `/login`
/// and asserts the resolved router location instead of the pushed widget.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/super_admin/mfa_challenge_handler.dart';
import 'package:veraprob/application/super_admin/mfa_result_view.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/super_admin/mfa_challenge_result.dart';
import 'package:veraprob/features/super_admin/presentation/screens/mfa_challenge_screen.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/mfa_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

class _MockMfaChallengeHandler extends Mock implements MfaChallengeHandler {}

class _MockAuthRepository extends Mock implements IAuthRepository {}

class _MockDateTimeProvider extends Mock implements IDateTimeProvider {}

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

const _kCode = '123456';

const _mfaPath = '/mfa';

typedef _Harness = ({Widget widget, GoRouter router});

_Harness _buildScreen({
  required _MockMfaChallengeHandler handler,
  required IDateTimeProvider timeProvider,
  IAuthRepository? authRepo,
}) {
  final overrides = <Override>[
    mfaChallengeHandlerProvider.overrideWithValue(handler),
    dateTimeProviderProvider.overrideWithValue(timeProvider),
    if (authRepo != null) authRepositoryProvider.overrideWithValue(authRepo),
  ];

  final router = GoRouter(
    initialLocation: _mfaPath,
    routes: [
      GoRoute(
        path: _mfaPath,
        builder: (context, state) => const MfaChallengeScreen(),
      ),
      GoRoute(
        path: AppRoutes.superAdminTenants,
        builder: (context, state) => const Text('route:tenants'),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const Text('route:login'),
      ),
    ],
  );

  final widget = ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
  return (widget: widget, router: router);
}

String _currentPath(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('MfaChallengeScreen — CT30', () {
    late _MockMfaChallengeHandler handler;
    late _MockDateTimeProvider timeProvider;
    late DateTime fixedNow;

    setUp(() {
      handler = _MockMfaChallengeHandler();
      timeProvider = _MockDateTimeProvider();
      fixedNow = DateTime(2026, 5, 12, 14, 0, 0).toUtc();

      when(() => timeProvider.nowUtc()).thenReturn(fixedNow);
      when(() => handler.createChallenge()).thenAnswer(
        (_) async => const MfaChallengeResult(
          challengeId: 'challenge-c1',
          factorId: 'factor-f1',
        ),
      );
    });

    Future<void> enterCode(WidgetTester tester) async {
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, _kCode);
      // _verifyCode is async — pump to flush microtasks.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('14 happy path → navigates to Tenants branch', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      when(
        () => handler.verify(
          factorId: 'factor-f1',
          challengeId: 'challenge-c1',
          code: _kCode,
        ),
      ).thenAnswer((_) async => const MfaVerificationSuccess());

      final harness = _buildScreen(
        handler: handler,
        timeProvider: timeProvider,
      );
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      await enterCode(tester);
      await tester.pumpAndSettle();

      expect(find.byType(MfaChallengeScreen), findsNothing);
      expect(_currentPath(harness.router), AppRoutes.superAdminTenants);
      verify(
        () => handler.verify(
          factorId: 'factor-f1',
          challengeId: 'challenge-c1',
          code: _kCode,
        ),
      ).called(1);
    });

    testWidgets('15 single failure decrements remaining attempts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      when(
        () => handler.verify(
          factorId: 'factor-f1',
          challengeId: 'challenge-c1',
          code: _kCode,
        ),
      ).thenAnswer(
        (_) async => const MfaVerificationFailure(
          failedAttempts: 1,
          isLockedOut: false,
          message: 'Código TOTP inválido.',
        ),
      );

      final harness = _buildScreen(
        handler: handler,
        timeProvider: timeProvider,
      );
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      await enterCode(tester);
      // Allow the failure path to settle and create a fresh challenge.
      await tester.pumpAndSettle();

      expect(find.text('4 de 5 tentativas restantes'), findsOneWidget);
      expect(find.text('Código TOTP inválido.'), findsOneWidget);
      expect(find.text('Verificação MFA'), findsOneWidget);
    });

    testWidgets('16 fifth failure renders lockout banner + countdown', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final lockedUntil = fixedNow.add(const Duration(minutes: 15));
      when(
        () => handler.verify(
          factorId: 'factor-f1',
          challengeId: 'challenge-c1',
          code: _kCode,
        ),
      ).thenAnswer(
        (_) async => MfaVerificationFailure(
          failedAttempts: 5,
          isLockedOut: true,
          lockedUntil: lockedUntil,
          message: 'Conta bloqueada por 15 minutos após 5 tentativas falhas.',
        ),
      );

      final harness = _buildScreen(
        handler: handler,
        timeProvider: timeProvider,
      );
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      await enterCode(tester);
      await tester.pump();
      await tester.pump();

      expect(find.text('Conta Temporariamente Bloqueada'), findsOneWidget);
      expect(find.textContaining('Tente novamente em '), findsOneWidget);
      expect(find.byIcon(Icons.lock_clock), findsOneWidget);
    });

    testWidgets('17 countdown text decrements monotonically', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Future enough to keep the lockout banner visible across the test
      // window. Real wall-clock advances during runAsync delays — we compare
      // formatted countdown values for monotonic decrease.
      final lockedUntil = fixedNow.add(const Duration(seconds: 30));
      when(
        () => handler.verify(
          factorId: 'factor-f1',
          challengeId: 'challenge-c1',
          code: _kCode,
        ),
      ).thenAnswer(
        (_) async => MfaVerificationFailure(
          failedAttempts: 5,
          isLockedOut: true,
          lockedUntil: lockedUntil,
          message: 'Bloqueado.',
        ),
      );

      final harness = _buildScreen(
        handler: handler,
        timeProvider: timeProvider,
      );
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();
      await enterCode(tester);
      await tester.pump();

      String captureCountdown() {
        final widget = tester.widgetList<Text>(
          find.textContaining('Tente novamente em '),
        );
        return widget.first.data ?? '';
      }

      final initial = captureCountdown();

      // Advance virtual clock by 2s.
      fixedNow = fixedNow.add(const Duration(seconds: 2));
      when(() => timeProvider.nowUtc()).thenReturn(fixedNow);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      final later = captureCountdown();

      expect(
        initial,
        isNot(equals(later)),
        reason: 'Countdown text must change as time passes.',
      );
      // Both values must follow the MM:SS format.
      final pattern = RegExp(r'Tente novamente em \d{2}:\d{2}');
      expect(pattern.hasMatch(initial), isTrue, reason: 'initial=$initial');
      expect(pattern.hasMatch(later), isTrue, reason: 'later=$later');
    });

    testWidgets('18 TextField is disabled while lockout is active', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final lockedUntil = fixedNow.add(const Duration(minutes: 15));
      when(
        () => handler.verify(
          factorId: 'factor-f1',
          challengeId: 'challenge-c1',
          code: _kCode,
        ),
      ).thenAnswer(
        (_) async => MfaVerificationFailure(
          failedAttempts: 5,
          isLockedOut: true,
          lockedUntil: lockedUntil,
          message: 'Bloqueado.',
        ),
      );

      final harness = _buildScreen(
        handler: handler,
        timeProvider: timeProvider,
      );
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();
      await enterCode(tester);
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('19 lockout auto-unlocks and creates a fresh challenge', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Lockout that will expire in 1.5 virtual seconds.
      final lockedUntil = fixedNow.add(const Duration(milliseconds: 1500));
      when(
        () => handler.verify(
          factorId: 'factor-f1',
          challengeId: 'challenge-c1',
          code: _kCode,
        ),
      ).thenAnswer(
        (_) async => MfaVerificationFailure(
          failedAttempts: 5,
          isLockedOut: true,
          lockedUntil: lockedUntil,
          message: 'Bloqueado.',
        ),
      );

      final harness = _buildScreen(
        handler: handler,
        timeProvider: timeProvider,
      );
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();
      await enterCode(tester);
      await tester.pump();

      expect(find.text('Conta Temporariamente Bloqueada'), findsOneWidget);

      // Advance virtual clock by 2s.
      fixedNow = fixedNow.add(const Duration(seconds: 2));
      when(() => timeProvider.nowUtc()).thenReturn(fixedNow);

      // Pump twice with the periodic timer interval to fire the unlock path.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Conta Temporariamente Bloqueada'), findsNothing);
      expect(find.text('Verificação MFA'), findsOneWidget);
      // createChallenge fires once on initState and a second time on auto-unlock.
      verify(() => handler.createChallenge()).called(2);
    });

    testWidgets('20 "Voltar ao Login" calls signOut and navigates', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final authRepo = _MockAuthRepository();
      when(() => authRepo.signOut()).thenAnswer((_) async {});
      when(
        () => authRepo.authStatusStream,
      ).thenAnswer((_) => const Stream<bool>.empty());

      final harness = _buildScreen(
        handler: handler,
        timeProvider: timeProvider,
        authRepo: authRepo,
      );
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Voltar ao Login'));
      await tester.pumpAndSettle();

      verify(() => authRepo.signOut()).called(1);
      expect(find.byType(MfaChallengeScreen), findsNothing);
      expect(_currentPath(harness.router), AppRoutes.login);
    });
  });
}
