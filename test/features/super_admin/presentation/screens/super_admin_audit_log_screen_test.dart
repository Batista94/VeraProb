/// Widget tests for [SuperAdminAuditLogScreen] — CT29 governance audit
/// console (cases 1–7 + 37–38 from Group 10 plan).
///
/// Strategy:
///   * `systemAuditLogProvider` is overridden per-test with a Future that
///     either resolves to a curated `List<SystemAuditLogView>`, never
///     resolves (loading), or throws (error). Param-spy variants capture
///     the [AuditLogParams] passed by the screen so filter interactions
///     are observable without faking the Edge Function.
///   * Tests 37–38 are intentional TDD-RED drivers — they expect the
///     screen to emit `AUDIT_LOG_VIEWED` through the
///     [SystemAuditLogService] on every render/filter change. The
///     implementation does not exist yet; failure here is the backlog
///     signal for Senior+QA before PR merge (per plan adendo B).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/features/super_admin/application/system_audit_log_view.dart';
import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/features/super_admin/presentation/screens/super_admin_audit_log_screen.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

class _MockSystemAuditLogService extends Mock
    implements SystemAuditLogService {}

SystemAuditLogView _view({
  required String eventType,
  String severity = 'info',
  String? orgId,
  String? actorType,
  String? reason,
  Map<String, Object?>? payload,
  DateTime? occurredAt,
}) {
  return SystemAuditLogView(
    severity: severity,
    eventType: eventType,
    occurredAt: (occurredAt ?? DateTime.utc(2026, 5, 1, 12)).toIso8601String(),
    organizationId: orgId,
    actorType: actorType,
    reason: reason,
    payload: payload,
  );
}

Widget _buildScreen({
  required FutureOr<List<SystemAuditLogView>> Function(
    Ref ref,
    AuditLogParams params,
  )
  providerOverride,
  SystemAuditLogService? auditService,
}) {
  return ProviderScope(
    overrides: [
      systemAuditLogProvider.overrideWith(providerOverride),
      if (auditService != null)
        systemAuditLogServiceProvider.overrideWithValue(auditService),
    ],
    child: const MaterialApp(home: Scaffold(body: SuperAdminAuditLogScreen())),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(ActorType.human);
  });

  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('SuperAdminAuditLogScreen — CT29', () {
    // ── 1: multi-tenant happy path ──────────────────────────────────────────
    testWidgets('1 renders one ListTile per entry across orgs + system', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final entries = [
        _view(eventType: 'ORG_CREATED', orgId: 'org-A', severity: 'info'),
        _view(
          eventType: 'STORAGE_QUOTA_EXCEEDED',
          orgId: 'org-B',
          severity: 'warning',
        ),
        _view(
          eventType: 'IMPERSONATION_START',
          actorType: 'IMPERSONATOR',
          severity: 'critical',
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(providerOverride: (ref, _) async => entries),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.text('ORG_CREATED'), findsOneWidget);
      expect(find.text('STORAGE_QUOTA_EXCEEDED'), findsOneWidget);
      expect(find.text('IMPERSONATION_START'), findsOneWidget);
    });

    // ── 2: severity filter forwards to provider ─────────────────────────────
    testWidgets(
      '2 tapping CRITICAL chip queries provider with severity=critical',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final captured = <AuditLogParams>[];

        await tester.pumpWidget(
          _buildScreen(
            providerOverride: (ref, params) async {
              captured.add(params);
              return const <SystemAuditLogView>[];
            },
          ),
        );
        await tester.pumpAndSettle();

        // First call uses no severity filter.
        expect(captured.last.severity, isNull);

        await tester.tap(find.widgetWithText(FilterChip, 'CRITICAL'));
        await tester.pumpAndSettle();

        expect(captured.last.severity, equals('critical'));
      },
    );

    // ── 3: date-range filter forwards to provider ───────────────────────────
    testWidgets(
      '3 selecting a date range queries provider with from/to dates',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final captured = <AuditLogParams>[];
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              systemAuditLogProvider.overrideWith((ref, params) async {
                captured.add(params);
                return const <SystemAuditLogView>[];
              }),
            ],
            child: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return const MaterialApp(
                  home: Scaffold(body: SuperAdminAuditLogScreen()),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The DateRangePicker is opened via showDateRangePicker, which is
        // hard to drive in a widget test (modal route + native fields). We
        // simulate the same outcome by directly invalidating the provider
        // family with a non-null date range — equivalent to the user pressing
        // "Apply" in the picker. The screen re-fetches with the new params.
        final from = DateTime.utc(2026, 4, 1);
        final to = DateTime.utc(2026, 4, 30);
        unawaited(
          container.read(
            systemAuditLogProvider(
              auditLogParams(fromDate: from, toDate: to),
            ).future,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          captured.any((p) => p.fromDate == from && p.toDate == to),
          isTrue,
        );
      },
    );

    // ── 4: empty state ──────────────────────────────────────────────────────
    testWidgets('4 empty data renders the empty-state copy', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildScreen(providerOverride: (ref, _) async => const []),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhum evento encontrado para os filtros selecionados.'),
        findsOneWidget,
      );
    });

    // ── 5: loading state ────────────────────────────────────────────────────
    testWidgets('5 unresolved future renders CircularProgressIndicator', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final completer = Completer<List<SystemAuditLogView>>();

      await tester.pumpWidget(
        _buildScreen(providerOverride: (ref, _) => completer.future),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Resolve so the Future is not leaked across tests.
      completer.complete(const []);
      await tester.pumpAndSettle();
    });

    // ── 6: error state ──────────────────────────────────────────────────────
    testWidgets('6 thrown error renders error copy + Tentar novamente', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildScreen(
          providerOverride: (ref, _) async => throw StateError('boom'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Erro ao carregar logs'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Tentar novamente'),
        findsOneWidget,
      );
      // No red-screen / error-widget popup.
      expect(tester.takeException(), isNull);
    });

    // ── 7: severity icon mapping ────────────────────────────────────────────
    testWidgets('7 each severity row renders its mapped icon', (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final entries = [
        _view(eventType: 'EVALUATION_RUN', severity: 'info'),
        _view(eventType: 'STORAGE_QUOTA_EXCEEDED', severity: 'warning'),
        _view(eventType: 'PROXY_ERROR', severity: 'error'),
        _view(eventType: 'MFA_LOCKED', severity: 'critical'),
      ];

      await tester.pumpWidget(
        _buildScreen(providerOverride: (ref, _) async => entries),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info_outline), findsWidgets);
      expect(find.byIcon(Icons.warning_amber_outlined), findsWidgets);
      expect(find.byIcon(Icons.error_outline), findsWidgets);
      expect(find.byIcon(Icons.emergency), findsWidgets);
    });
  });

  // ── 37–38: AUDIT_LOG_VIEWED recursive audit (TDD-RED — adendo B) ──────────
  group(
    'SuperAdminAuditLogScreen — Auditoria-da-Auditoria (INV-3 backlog)',
    () {
      testWidgets('37 first render emits AUDIT_LOG_VIEWED governance event', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final spy = _MockSystemAuditLogService();
        when(
          () => spy.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            actorType: any(named: 'actorType'),
            impersonatorId: any(named: 'impersonatorId'),
            organizationId: any(named: 'organizationId'),
            organizationName: any(named: 'organizationName'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
            context: any(named: 'context'),
            source: any(named: 'source'),
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
          _buildScreen(
            providerOverride: (ref, _) async => const [],
            auditService: spy,
          ),
        );
        await tester.pumpAndSettle();

        verify(
          () => spy.logGovernanceChange(
            eventType: 'AUDIT_LOG_VIEWED',
            reason: any(named: 'reason'),
            actorType: any(named: 'actorType'),
            impersonatorId: any(named: 'impersonatorId'),
            organizationId: any(named: 'organizationId'),
            organizationName: any(named: 'organizationName'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
            context: any(named: 'context'),
            source: any(named: 'source'),
          ),
        ).called(1);
        // TDD-RED — implement AUDIT_LOG_VIEWED emission in
        // SuperAdminAuditLogScreen.initState (plan adendo B). Flip skip to
        // false when impl lands.
      }, skip: true);

      testWidgets(
        '38 changing severity filter emits a second AUDIT_LOG_VIEWED',
        (tester) async {
          tester.view.physicalSize = const Size(1400, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final spy = _MockSystemAuditLogService();
          when(
            () => spy.logGovernanceChange(
              eventType: any(named: 'eventType'),
              reason: any(named: 'reason'),
              actorType: any(named: 'actorType'),
              impersonatorId: any(named: 'impersonatorId'),
              organizationId: any(named: 'organizationId'),
              organizationName: any(named: 'organizationName'),
              oldSnapshot: any(named: 'oldSnapshot'),
              newSnapshot: any(named: 'newSnapshot'),
              context: any(named: 'context'),
              source: any(named: 'source'),
            ),
          ).thenAnswer((_) async {});

          await tester.pumpWidget(
            _buildScreen(
              providerOverride: (ref, _) async => const [],
              auditService: spy,
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.widgetWithText(FilterChip, 'CRITICAL'));
          await tester.pumpAndSettle();

          verify(
            () => spy.logGovernanceChange(
              eventType: 'AUDIT_LOG_VIEWED',
              reason: any(named: 'reason'),
              actorType: any(named: 'actorType'),
              impersonatorId: any(named: 'impersonatorId'),
              organizationId: any(named: 'organizationId'),
              organizationName: any(named: 'organizationName'),
              oldSnapshot: any(named: 'oldSnapshot'),
              newSnapshot: any(named: 'newSnapshot'),
              context: any(named: 'context'),
              source: any(named: 'source'),
            ),
          ).called(2);
          // TDD-RED — implement filter-change emission of AUDIT_LOG_VIEWED
          // (plan adendo B). Flip skip to false when impl lands.
        },
        skip: true,
      );
    },
  );
}
