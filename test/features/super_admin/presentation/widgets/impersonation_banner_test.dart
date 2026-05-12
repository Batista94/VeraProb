import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/super_admin/revoke_impersonation_handler.dart';
import 'package:veraprob/application/super_admin/start_impersonation_handler.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/impersonation_banner.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

class MockRevokeImpersonationHandler extends Mock
    implements RevokeImpersonationHandler {}

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

void main() {
  late MockRevokeImpersonationHandler mockHandler;
  late MockDateTimeProvider mockDateTimeProvider;
  late DateTime baseTime;

  setUp(() {
    mockHandler = MockRevokeImpersonationHandler();
    mockDateTimeProvider = MockDateTimeProvider();
    baseTime = DateTime(2026, 5, 11, 12, 0, 0).toUtc();

    when(() => mockDateTimeProvider.nowUtc()).thenReturn(baseTime);
  });

  Widget wrap(Widget child, ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              child,
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
  }

  ImpersonationSessionInfo createSession({
    Duration remaining = const Duration(minutes: 5),
  }) {
    return ImpersonationSessionInfo(
      sessionId: 'session-123',
      targetOrgId: 'org-456',
      targetOrgName: 'ACME Corp',
      impersonatorId: 'admin-789',
      issuedAt: baseTime.subtract(const Duration(minutes: 1)),
      expiresAt: baseTime.add(remaining),
      dateTimeProvider: mockDateTimeProvider,
    );
  }

  group('ImpersonationBanner — Functional & Happy Path', () {
    testWidgets('renders correct organization name', (tester) async {
      final session = createSession();
      final container = ProviderContainer();

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(session: session, onSessionEnded: () {}),
          container,
        ),
      );

      expect(find.textContaining('ACME Corp'), findsOneWidget);
      expect(find.textContaining('MODO IMPERSONATION'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('formats and decrements timer correctly', (tester) async {
      final session = createSession(remaining: const Duration(minutes: 5));
      final container = ProviderContainer();

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(session: session, onSessionEnded: () {}),
          container,
        ),
      );

      // Initial state: 05:00
      expect(find.text('05:00'), findsOneWidget);

      // Advance time by 1 second in mock
      when(
        () => mockDateTimeProvider.nowUtc(),
      ).thenReturn(baseTime.add(const Duration(seconds: 1)));

      // Trigger ticker
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('04:59'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('calls onSessionEnded when timer reaches zero', (tester) async {
      bool endedCalled = false;
      final session = createSession(remaining: const Duration(seconds: 1));
      final container = ProviderContainer();

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(
            session: session,
            onSessionEnded: () => endedCalled = true,
          ),
          container,
        ),
      );

      // Advance time to expiration
      when(
        () => mockDateTimeProvider.nowUtc(),
      ).thenReturn(baseTime.add(const Duration(seconds: 1)));

      await tester.pump(const Duration(seconds: 1));

      expect(endedCalled, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('manual revocation success calls handler and onSessionEnded', (
      tester,
    ) async {
      bool endedCalled = false;
      final session = createSession();

      when(
        () => mockHandler.handle(
          impersonationSessionId: any(named: 'impersonationSessionId'),
          targetOrgId: any(named: 'targetOrgId'),
          callerSessionId: any(named: 'callerSessionId'),
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) async => {});

      final container = ProviderContainer(
        overrides: [
          revokeImpersonationHandlerProvider.overrideWithValue(mockHandler),
        ],
      );

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(
            session: session,
            onSessionEnded: () => endedCalled = true,
          ),
          container,
        ),
      );

      await tester.tap(find.text('Encerrar Sessão'));
      await tester.pump(); // Start async

      verify(
        () => mockHandler.handle(
          impersonationSessionId: 'session-123',
          targetOrgId: 'org-456',
          callerSessionId: 'session-123',
          reason: 'Manual revocation by super_admin',
        ),
      ).called(1);

      // Handler is async, pump to let it finish
      await tester.pump();
      expect(endedCalled, isTrue);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('ImpersonationBanner — UX & Operations (Industrial Deep)', () {
    testWidgets('uses correct high-visibility red color', (tester) async {
      final session = createSession();
      final container = ProviderContainer();

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(session: session, onSessionEnded: () {}),
          container,
        ),
      );

      final containerWidget = tester.widget<Container>(
        find.byType(Container).first,
      );
      expect(containerWidget.color, const Color(0xFFB00020));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows loading state and disables button during revocation', (
      tester,
    ) async {
      final session = createSession();
      final completer = Completer<void>();

      when(
        () => mockHandler.handle(
          impersonationSessionId: any(named: 'impersonationSessionId'),
          targetOrgId: any(named: 'targetOrgId'),
          callerSessionId: any(named: 'callerSessionId'),
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) => completer.future);

      final container = ProviderContainer(
        overrides: [
          revokeImpersonationHandlerProvider.overrideWithValue(mockHandler),
        ],
      );

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(session: session, onSessionEnded: () {}),
          container,
        ),
      );

      await tester.tap(find.text('Encerrar Sessão'));
      await tester.pump(); // Rebuild with loading state

      // Verify loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Verify button is disabled (onPressed is null)
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(button.onPressed, isNull);

      completer.complete();
      await tester.pump(); // Finish future and rebuild

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('ImpersonationBanner — Security & Adversarial (QA Security)', () {
    testWidgets('prevents double-clicks via loading state', (tester) async {
      final session = createSession();
      final container = ProviderContainer(
        overrides: [
          revokeImpersonationHandlerProvider.overrideWithValue(mockHandler),
        ],
      );

      when(
        () => mockHandler.handle(
          impersonationSessionId: any(named: 'impersonationSessionId'),
          targetOrgId: any(named: 'targetOrgId'),
          callerSessionId: any(named: 'callerSessionId'),
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 100));
      });

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(session: session, onSessionEnded: () {}),
          container,
        ),
      );

      // Tap twice rapidly
      await tester.tap(find.text('Encerrar Sessão'));
      await tester.tap(find.text('Encerrar Sessão'));
      await tester.pump(); // Trigger build

      // Should only be called once because of _isRevoking check
      verify(
        () => mockHandler.handle(
          impersonationSessionId: any(named: 'impersonationSessionId'),
          targetOrgId: any(named: 'targetOrgId'),
          callerSessionId: any(named: 'callerSessionId'),
          reason: any(named: 'reason'),
        ),
      ).called(1);

      // Clean up the pending future to avoid timer issues
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'handles revocation failure: shows SnackBar and stays visible',
      (tester) async {
        final session = createSession();

        when(
          () => mockHandler.handle(
            impersonationSessionId: any(named: 'impersonationSessionId'),
            targetOrgId: any(named: 'targetOrgId'),
            callerSessionId: any(named: 'callerSessionId'),
            reason: any(named: 'reason'),
          ),
        ).thenThrow(Exception('Network Error'));

        final container = ProviderContainer(
          overrides: [
            revokeImpersonationHandlerProvider.overrideWithValue(mockHandler),
          ],
        );

        await tester.pumpWidget(
          wrap(
            ImpersonationBanner(session: session, onSessionEnded: () {}),
            container,
          ),
        );

        await tester.tap(find.text('Encerrar Sessão'));
        await tester.pump(); // Start revocation
        await tester.pump(); // Process error and show SnackBar

        // Verify SnackBar
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining('Erro ao revogar'), findsOneWidget);
        expect(find.textContaining('Network Error'), findsOneWidget);

        // Verify banner is still visible
        expect(find.textContaining('MODO IMPERSONATION'), findsOneWidget);

        // Verify button is re-enabled
        final button = tester.widget<TextButton>(find.byType(TextButton));
        expect(button.onPressed, isNotNull);

        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('ImpersonationBanner — Visual Regression & Semantics', () {
    testWidgets('golden test — default state', (tester) async {
      tester.view.physicalSize = const Size(800, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = createSession();
      final container = ProviderContainer();

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(session: session, onSessionEnded: () {}),
          container,
        ),
      );

      // Verify golden
      await expectLater(
        find.byType(ImpersonationBanner),
        matchesGoldenFile('goldens/impersonation_banner_default.png'),
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('golden test — revoking state', (tester) async {
      tester.view.physicalSize = const Size(800, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = createSession();
      final completer = Completer<void>();

      when(
        () => mockHandler.handle(
          impersonationSessionId: any(named: 'impersonationSessionId'),
          targetOrgId: any(named: 'targetOrgId'),
          callerSessionId: any(named: 'callerSessionId'),
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) => completer.future);

      final container = ProviderContainer(
        overrides: [
          revokeImpersonationHandlerProvider.overrideWithValue(mockHandler),
        ],
      );

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(session: session, onSessionEnded: () {}),
          container,
        ),
      );

      await tester.tap(find.text('Encerrar Sessão'));
      await tester.pump(); // Show loading state

      // Verify golden with spinner
      await expectLater(
        find.byType(ImpersonationBanner),
        matchesGoldenFile('goldens/impersonation_banner_revoking.png'),
      );

      completer.complete();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('semantics — verify accessibility labels', (tester) async {
      final session = createSession();
      final container = ProviderContainer();

      await tester.pumpWidget(
        wrap(
          ImpersonationBanner(session: session, onSessionEnded: () {}),
          container,
        ),
      );

      // Check for org name in semantics
      expect(
        tester.getSemantics(find.textContaining('ACME Corp')),
        matchesSemantics(label: 'MODO IMPERSONATION — Atuando como: ACME Corp'),
      );

      // Check for button semantics
      expect(
        tester.getSemantics(find.text('Encerrar Sessão')),
        matchesSemantics(
          label: 'Encerrar Sessão',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.pumpWidget(const SizedBox());
    });
  });
}
