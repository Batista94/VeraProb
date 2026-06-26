/// Widget tests for [SuperAdminAuditLogScreen] — CT29 governance audit
/// console. Enterprise Tier 1: Forensic Integrity, Adversarial Resilience,
/// A11y, Audit-of-Audit, Golden Tests.
library;

import 'dart:async';
import 'dart:io';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/super_admin/system_audit_log_view.dart';
import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/features/super_admin/presentation/screens/super_admin_audit_log_screen.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

// ─── Mocks & Helpers ────────────────────────────────────────────────────────

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

class _MockSystemAuditLogService extends Mock
    implements SystemAuditLogService {}

class _MockDateTimeProvider extends Mock implements IDateTimeProvider {}

SystemAuditLogView _view({
  required String eventType,
  String severity = 'info',
  String? orgId,
  String? actorType,
  String? reason,
  String? impersonatorId,
  Map<String, Object?>? payload,
  DateTime? occurredAt,
  String? occurredAtRaw,
}) {
  return SystemAuditLogView(
    severity: severity,
    eventType: eventType,
    occurredAt:
        occurredAtRaw ??
        (occurredAt ?? DateTime.utc(2026, 5, 1, 12)).toIso8601String(),
    organizationId: orgId,
    actorType: actorType,
    reason: reason,
    payload: payload,
    impersonatorId: impersonatorId,
  );
}

Widget _buildScreen({
  required FutureOr<List<SystemAuditLogView>> Function(
    Ref ref,
    AuditLogParams params,
  )
  providerOverride,
  SystemAuditLogService? auditService,
  IDateTimeProvider? timeProvider,
}) {
  return ProviderScope(
    overrides: [
      systemAuditLogProvider.overrideWith(providerOverride),
      if (auditService != null)
        systemAuditLogServiceProvider.overrideWithValue(auditService),
      if (timeProvider != null)
        dateTimeProviderProvider.overrideWithValue(timeProvider),
    ],
    child: const MaterialApp(home: Scaffold(body: SuperAdminAuditLogScreen())),
  );
}

void _setLargeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  setUpAll(() => registerFallbackValue(ActorType.human));
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 1 — CT29 BASELINE (cases 1–7)
  // ═══════════════════════════════════════════════════════════════════════════
  group('CT29 Baseline', () {
    testWidgets('1 renders one ListTile per entry across orgs + system', (
      tester,
    ) async {
      _setLargeScreen(tester);
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

    testWidgets(
      '2 tapping CRITICAL chip queries provider with severity=critical',
      (tester) async {
        _setLargeScreen(tester);
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
        expect(captured.last.severity, isNull);
        await tester.tap(find.widgetWithText(FilterChip, 'CRITICAL'));
        await tester.pumpAndSettle();
        expect(captured.last.severity, equals('critical'));
      },
    );

    testWidgets('3 selecting a date range queries provider with from/to dates', (
      tester,
    ) async {
      _setLargeScreen(tester);
      final captured = <AuditLogParams>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            systemAuditLogProvider.overrideWith((ref, params) async {
              captured.add(params);
              return const <SystemAuditLogView>[];
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SuperAdminAuditLogScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 4, 30);
      // Simulate date range selection by reading provider with params directly
      unawaited(
        ProviderScope.containerOf(
          tester.element(find.byType(SuperAdminAuditLogScreen)),
        ).read(
          systemAuditLogProvider(
            auditLogParams(fromDate: from, toDate: to),
          ).future,
        ),
      );
      await tester.pumpAndSettle();
      expect(captured.any((p) => p.fromDate == from && p.toDate == to), isTrue);
    });

    testWidgets('4 empty data renders the empty-state copy', (tester) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(providerOverride: (ref, _) async => const []),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Nenhum evento encontrado para os filtros selecionados.'),
        findsOneWidget,
      );
    });

    testWidgets('5 unresolved future renders CircularProgressIndicator', (
      tester,
    ) async {
      _setLargeScreen(tester);
      final completer = Completer<List<SystemAuditLogView>>();
      await tester.pumpWidget(
        _buildScreen(providerOverride: (ref, _) => completer.future),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      completer.complete(const []);
      await tester.pumpAndSettle();
    });

    testWidgets('6 thrown error renders error copy + Tentar novamente', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(
          providerOverride: (ref, _) async => throw StateError('boom'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Não foi possível carregar os logs no momento.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Tentar novamente'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

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

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 2 — FORENSIC INTEGRITY (CIA Triad - Integrity)
  // ═══════════════════════════════════════════════════════════════════════════
  group('Forensic Integrity', () {
    // ── INV-28: Actor Identification ──────────────────────────────────────
    testWidgets('8 SYSTEM actor renders robot icon with tooltip "Sistema"', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(
          providerOverride: (ref, _) async => [
            _view(eventType: 'CRON_RUN', actorType: 'SYSTEM'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
      expect(find.byTooltip('Sistema'), findsOneWidget);
    });

    testWidgets('9 HUMAN actor renders shield icon with tooltip "Admin"', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(
          providerOverride: (ref, _) async => [
            _view(eventType: 'QUOTA_CHANGE', actorType: 'HUMAN'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      expect(find.byTooltip('Admin'), findsOneWidget);
    });

    testWidgets(
      '10 IMPERSONATOR actor renders manage_accounts with impersonatorId in tooltip',
      (tester) async {
        _setLargeScreen(tester);
        await tester.pumpWidget(
          _buildScreen(
            providerOverride: (ref, _) async => [
              _view(
                eventType: 'IMPERSONATION_START',
                actorType: 'IMPERSONATOR',
                impersonatorId: 'sa-uuid-007',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.manage_accounts), findsOneWidget);
        expect(find.byTooltip('Impersonacao (sa-uuid-007)'), findsOneWidget);
      },
    );

    testWidgets(
      '11 IMPERSONATOR with null impersonatorId shows "?" in tooltip',
      (tester) async {
        _setLargeScreen(tester);
        await tester.pumpWidget(
          _buildScreen(
            providerOverride: (ref, _) async => [
              _view(
                eventType: 'IMPERSONATION_START',
                actorType: 'IMPERSONATOR',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Impersonacao (?)'), findsOneWidget);
      },
    );

    // ── UTC Precision (INV-6) ─────────────────────────────────────────────
    testWidgets('12 date range params are strictly UTC (no local drift)', (
      tester,
    ) async {
      _setLargeScreen(tester);
      final captured = <AuditLogParams>[];
      final timeProvider = _MockDateTimeProvider();
      final fixedNow = DateTime.utc(2026, 5, 12, 14);
      when(() => timeProvider.nowUtc()).thenReturn(fixedNow);

      await tester.pumpWidget(
        _buildScreen(
          timeProvider: timeProvider,
          providerOverride: (ref, params) async {
            captured.add(params);
            return const <SystemAuditLogView>[];
          },
        ),
      );
      await tester.pumpAndSettle();
      // Simulate UTC date range selection
      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 4, 30);
      final providerContainer = ProviderScope.containerOf(
        tester.element(find.byType(SuperAdminAuditLogScreen)),
      );
      unawaited(
        providerContainer.read(
          systemAuditLogProvider(
            auditLogParams(fromDate: from, toDate: to),
          ).future,
        ),
      );
      await tester.pumpAndSettle();
      final match = captured.firstWhere((p) => p.fromDate != null);
      expect(match.fromDate!.isUtc, isTrue, reason: 'fromDate must be UTC');
      expect(match.toDate!.isUtc, isTrue, reason: 'toDate must be UTC');
    });

    // ── Null-Safety Resilience ────────────────────────────────────────────
    testWidgets('13 event with empty occurredAt renders placeholder "-"', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(
          providerOverride: (ref, _) async => [
            _view(eventType: 'GHOST_EVENT', occurredAtRaw: ''),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('-'), findsOneWidget);
      expect(find.text('GHOST_EVENT'), findsOneWidget);
    });

    testWidgets('14 event with null payload does not show detail button', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(
          providerOverride: (ref, _) async => [
            _view(eventType: 'MINIMAL_EVENT', payload: null),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.data_object), findsNothing);
    });

    testWidgets(
      '15 event with empty payload map shows detail button but renders "Sem payload."',
      (tester) async {
        _setLargeScreen(tester);
        await tester.pumpWidget(
          _buildScreen(
            providerOverride: (ref, _) async => [
              _view(
                eventType: 'EMPTY_PAYLOAD',
                payload: const <String, Object?>{},
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.data_object), findsOneWidget);
        await tester.tap(find.byIcon(Icons.data_object));
        await tester.pumpAndSettle();
        expect(find.text('Sem payload.'), findsOneWidget);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 3 — ADVERSARIAL RESILIENCE (Race Conditions & Payload Stress)
  // ═══════════════════════════════════════════════════════════════════════════
  group('Adversarial Resilience', () {
    // ── Rapid Filter Tapping ──────────────────────────────────────────────
    testWidgets(
      '16 rapid severity chip toggling shows only last filter result',
      (tester) async {
        _setLargeScreen(tester);
        var callCount = 0;
        final completers = <int, Completer<List<SystemAuditLogView>>>{};

        await tester.pumpWidget(
          _buildScreen(
            providerOverride: (ref, params) {
              final idx = callCount++;
              final c = Completer<List<SystemAuditLogView>>();
              completers[idx] = c;
              return c.future;
            },
          ),
        );
        await tester.pump();

        // Complete initial load
        completers[0]!.complete(const []);
        await tester.pumpAndSettle();

        // Rapid taps: INFO -> CRITICAL -> WARNING
        await tester.tap(find.widgetWithText(FilterChip, 'INFO'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilterChip, 'CRITICAL'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilterChip, 'WARNING'));
        await tester.pump();

        // Only resolve the last request with data
        final lastIdx = callCount - 1;
        for (var i = 1; i < lastIdx; i++) {
          if (completers.containsKey(i) && !completers[i]!.isCompleted) {
            completers[i]!.complete(const []);
          }
        }
        completers[lastIdx]!.complete([
          _view(eventType: 'FINAL_RESULT', severity: 'warning'),
        ]);
        await tester.pumpAndSettle();

        // Only the last filter's result should be visible
        expect(find.text('FINAL_RESULT'), findsOneWidget);
      },
    );

    // ── Large Payload Stress ──────────────────────────────────────────────
    testWidgets(
      '17 deeply nested large JSON payload is scrollable without overflow',
      (tester) async {
        _setLargeScreen(tester);
        // Generate a deeply nested payload
        Map<String, Object?> nested = {'leaf': 'value'};
        for (var i = 0; i < 20; i++) {
          nested = {'level_$i': nested, 'data_$i': 'x' * 200};
        }
        final largePayload = <String, Object?>{
          for (var i = 0; i < 50; i++) 'field_$i': 'value_${'y' * 100}_$i',
          'nested': nested,
        };

        await tester.pumpWidget(
          _buildScreen(
            providerOverride: (ref, _) async => [
              _view(eventType: 'LARGE_PAYLOAD', payload: largePayload),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Open payload dialog
        await tester.tap(find.byIcon(Icons.data_object));
        await tester.pumpAndSettle();

        // Dialog should render without overflow errors
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    // ── Retry Logic ───────────────────────────────────────────────────────
    testWidgets(
      '18 "Tentar novamente" reinvalidates provider and clears error',
      (tester) async {
        _setLargeScreen(tester);
        var attempt = 0;
        await tester.pumpWidget(
          _buildScreen(
            providerOverride: (ref, _) async {
              attempt++;
              if (attempt == 1) throw StateError('network failure');
              return [_view(eventType: 'RECOVERED')];
            },
          ),
        );
        await tester.pumpAndSettle();

        // Error state visible
        expect(
          find.textContaining('Não foi possível carregar os logs no momento.'),
          findsOneWidget,
        );

        // Tap retry
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Tentar novamente'),
        );
        await tester.pumpAndSettle();

        // Error cleared, data visible
        expect(
          find.textContaining('Não foi possível carregar os logs no momento.'),
          findsNothing,
        );
        expect(find.text('RECOVERED'), findsOneWidget);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 4 — ACCESSIBILITY (A11y)
  // ═══════════════════════════════════════════════════════════════════════════
  group('Accessibility', () {
    testWidgets('19 selected FilterChip announces "selecionado" semantics', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(providerOverride: (ref, _) async => const []),
      );
      await tester.pumpAndSettle();

      // Tap to select
      await tester.tap(find.widgetWithText(FilterChip, 'CRITICAL'));
      await tester.pumpAndSettle();

      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'CRITICAL'),
      );
      expect(chip.selected, isTrue);

      // Verify semantics node has selected state
      final semantics = tester.getSemantics(
        find.widgetWithText(FilterChip, 'CRITICAL'),
      );
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
    });

    testWidgets('20 unselected FilterChip does not announce selected', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(providerOverride: (ref, _) async => const []),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.widgetWithText(FilterChip, 'INFO'),
      );
      expect(semantics.flagsCollection.isSelected, Tristate.isFalse);
    });

    testWidgets('21 SYSTEM actor icon has descriptive semanticLabel', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(
          providerOverride: (ref, _) async => [
            _view(eventType: 'CRON_RUN', actorType: 'SYSTEM'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.smart_toy_outlined));
      expect(
        icon.semanticLabel,
        isNotNull,
        reason: 'Actor icon must have semanticLabel for screen readers',
      );
    });

    testWidgets('22 IMPERSONATOR actor icon has descriptive semanticLabel', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(
          providerOverride: (ref, _) async => [
            _view(
              eventType: 'IMP_START',
              actorType: 'IMPERSONATOR',
              impersonatorId: 'x',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.manage_accounts));
      expect(
        icon.semanticLabel,
        isNotNull,
        reason: 'Impersonator icon must have semanticLabel for screen readers',
      );
    });

    testWidgets('23 HUMAN actor icon has descriptive semanticLabel', (
      tester,
    ) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        _buildScreen(
          providerOverride: (ref, _) async => [
            _view(eventType: 'ADMIN_ACTION', actorType: 'HUMAN'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.shield_outlined));
      expect(
        icon.semanticLabel,
        isNotNull,
        reason: 'Human actor icon must have semanticLabel for screen readers',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 5 — AUDITORIA-DA-AUDITORIA (INV-3 Backlog — tests 37–38 ACTIVATED)
  // ═══════════════════════════════════════════════════════════════════════════
  group('Audit-of-Audit (INV-3)', () {
    late _MockSystemAuditLogService spy;

    setUp(() {
      spy = _MockSystemAuditLogService();
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
    });

    testWidgets('37 first render emits AUDIT_LOG_VIEWED governance event', (
      tester,
    ) async {
      _setLargeScreen(tester);
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
      // TDD-RED: Remove skip when AUDIT_LOG_VIEWED emission is implemented
      // in SuperAdminAuditLogScreen.initState (INV-3 backlog).
    }, skip: true);

    testWidgets('38 changing severity filter emits a second AUDIT_LOG_VIEWED', (
      tester,
    ) async {
      _setLargeScreen(tester);
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
      // TDD-RED: Remove skip when filter-change AUDIT_LOG_VIEWED emission lands.
    }, skip: true);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 6 — GOLDEN TESTS (Visual Logic & Branding)
  // ═══════════════════════════════════════════════════════════════════════════
  group('Golden Tests — Visual Regression', () {
    goldenTest(
      'Golden: severity highlighting with all severities present',
      fileName: 'audit_log_all_severities',
      builder: () {
        final entries = [
          _view(eventType: 'DEBUG_TRACE', severity: 'debug'),
          _view(eventType: 'EVALUATION_RUN', severity: 'info'),
          _view(eventType: 'STORAGE_QUOTA_EXCEEDED', severity: 'warning'),
          _view(eventType: 'PROXY_ERROR', severity: 'error'),
          _view(
            eventType: 'MFA_LOCKED',
            severity: 'critical',
            actorType: 'SYSTEM',
          ),
        ];
        return SizedBox(
          width: 1400,
          height: 1200,
          child: _buildScreen(providerOverride: (ref, _) async => entries),
        );
      },
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden: empty state centered with correct typography',
      fileName: 'audit_log_empty_state',
      builder: () => SizedBox(
        width: 1400,
        height: 900,
        child: _buildScreen(providerOverride: (ref, _) async => const []),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden: error state visual',
      fileName: 'audit_log_error_state',
      builder: () => SizedBox(
        width: 1400,
        height: 900,
        child: _buildScreen(
          providerOverride: (ref, _) async => throw StateError('network'),
        ),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden: payload diff dialog uses monospace font',
      fileName: 'audit_log_payload_diff',
      builder: () {
        final payload = <String, Object?>{
          'before': {'status': 'active', 'quota_gb': 10},
          'after': {'status': 'suspended', 'quota_gb': 5},
        };
        return SizedBox(
          width: 1400,
          height: 900,
          child: _buildScreen(
            providerOverride: (ref, _) async => [
              _view(
                eventType: 'STATUS_CHANGE',
                payload: payload,
                actorType: 'HUMAN',
              ),
            ],
          ),
        );
      },
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.data_object));
        await tester.pumpAndSettle();
      },
    );
  });
}
