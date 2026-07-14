// Goldens for ImpersonationBanner — generate EXCLUSIVAMENTE via `make goldens`.

import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/super_admin/revoke_impersonation_handler.dart';
import 'package:veraprob/application/super_admin/start_impersonation_handler.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
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

  group('ImpersonationBanner — Visual Regression (Goldens)', () {
    goldenTest(
      'golden test — default state',
      fileName: 'impersonation_banner_default',
      builder: () {
        final session = createSession();
        final container = ProviderContainer();
        return SizedBox(
          width: 800,
          height: 200,
          child: wrap(
            ImpersonationBanner(session: session, onSessionEnded: () {}),
            container,
          ),
        );
      },
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'golden test — revoking state',
      fileName: 'impersonation_banner_revoking',
      builder: () {
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

        return SizedBox(
          width: 800,
          height: 200,
          child: wrap(
            ImpersonationBanner(session: session, onSessionEnded: () {}),
            container,
          ),
        );
      },
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tester.tap(find.text('Encerrar Sessão'));
        await tester.pump();
      },
    );
  });
}
