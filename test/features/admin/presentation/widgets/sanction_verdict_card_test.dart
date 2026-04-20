import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/features/admin/presentation/widgets/sanction_verdict_card.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sanction_focus_provider.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/state/providers/investigation_providers.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/investigation_modal.dart';

import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/approve_sanction_handler.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_handler.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

class _MockDateTimeProvider implements IDateTimeProvider {
  final DateTime _now;
  _MockDateTimeProvider(this._now);
  @override
  DateTime nowUtc() => _now;
  @override
  DateTime nowBrazil() => _now;
}

class _MockAuthRepo implements IAuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockTenantValidationService extends TenantValidationService {
  _MockTenantValidationService() : super(authRepository: _MockAuthRepo());

  @override
  Future<void> assertTenantMatches({
    required String payloadOrgId,
    required String sessionId,
  }) async {}

  @override
  void verifySourceOwnership({
    required String resourceOrgId,
    required String requesterOrgId,
    String? resourceType,
    String? resourceId,
  }) {}
}

class _MockQueueRepo implements SanctionReviewQueueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockLedgerRepo implements SlaAuditLedgerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _fixedUtc = DateTime.utc(2026, 1, 15, 12, 0);

class _MockApproveHandler extends ApproveSanctionHandler {
  _MockApproveHandler()
    : super(
        tenantValidator: _MockTenantValidationService(),
        queueRepo: _MockQueueRepo(),
        ledger: _MockLedgerRepo(),
        rbac: RbacService(),
        dateTimeProvider: _MockDateTimeProvider(_fixedUtc),
      );
}

class _MockRejectHandler extends RejectSanctionHandler {
  _MockRejectHandler()
    : super(
        tenantValidator: _MockTenantValidationService(),
        queueRepo: _MockQueueRepo(),
        ledger: _MockLedgerRepo(),
        rbac: RbacService(),
        clock: _MockDateTimeProvider(_fixedUtc),
      );
}

class _LoadingActionNotifier extends SanctionActionNotifier {
  _LoadingActionNotifier()
    : super(
        approveHandler: _MockApproveHandler(),
        rejectHandler: _MockRejectHandler(),
      );

  @override
  AsyncValue<void> get state => const AsyncLoading();
}

class _ErrorActionNotifier extends SanctionActionNotifier {
  _ErrorActionNotifier()
    : super(
        approveHandler: _MockApproveHandler(),
        rejectHandler: _MockRejectHandler(),
      );

  @override
  AsyncValue<void> get state =>
      const AsyncError('mock approve failure', StackTrace.empty);
}

class _MockSanctionActionNotifier extends SanctionActionNotifier {
  _MockSanctionActionNotifier()
    : super(
        approveHandler: _MockApproveHandler(),
        rejectHandler: _MockRejectHandler(),
      );

  int approveCalls = 0;
  int rejectCalls = 0;

  @override
  Future<void> approve({
    required String queueEntryId,
    required String approvedByUserId,
    required String actorEmail,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    approveCalls++;
    state = const AsyncData(null);
  }

  @override
  Future<void> reject({
    required String queueEntryId,
    required String rejectedByUserId,
    required String actorEmail,
    required String rejectionReason,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    rejectCalls++;
    state = const AsyncData(null);
  }
}

SanctionQueueItemView _makeItem({
  int fineCents = 150000,
  int confidenceScore = 95,
  SanctionReviewStatus status = SanctionReviewStatus.pending,
  double? geofenceCenterLat,
  double? geofenceCenterLng,
  double? geofenceRadiusMeters,
  String id = 'test-id-001',
  String contractId = 'contract-001',
}) {
  final evidence = VerdictEvidence.create(
    clauseRef: 'ATR-01',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5,
    primaryEvidenceLng: -46.6,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 1, 15, 10, 0),
    deltaValue: 5.0,
    thresholdValue: 0.0,
    fineCents: Money(fineCents),
    confidenceScore: confidenceScore,
    geofenceCenterLat: geofenceCenterLat,
    geofenceCenterLng: geofenceCenterLng,
    geofenceRadiusMeters: geofenceRadiusMeters,
  );
  return SanctionQueueItemView(
    id: id,
    organizationId: 'org-001',
    ledgerEntryId: 'ledger-001',
    setId: 'set-001',
    contractId: contractId,
    verdictEvidence: evidence,
    status: status,
    createdAtUtc: DateTime.utc(2026, 1, 15, 10, 0),
  );
}

List<Override> _baseOverrides({
  required SanctionQueueItemView item,
  required SanctionActionNotifier notifier,
  String? contractName = 'Test Contract',
}) {
  return [
    contractNameProvider.overrideWith((ref, id) async => contractName),
    pendingSanctionsStreamProvider.overrideWith((ref) => Stream.value([item])),
    sanctionWindowProvider.overrideWith((ref, setId) async => null),
    sanctionActionStateProvider.overrideWith((ref, id) => notifier),
    tenantValidationServiceProvider.overrideWithValue(
      _MockTenantValidationService(),
    ),
    currentOperatorIdProvider.overrideWithValue('test-user'),
    currentOperatorEmailProvider.overrideWithValue('test@example.com'),
    currentSessionIdProvider.overrideWithValue('test-session'),
    dateTimeProviderProvider.overrideWithValue(
      _MockDateTimeProvider(_fixedUtc),
    ),
    vehicleInfractionRecurrenceProvider.overrideWith((ref, key) async => null),
    evaluationTracesProvider.overrideWith((ref, id) async => const []),
    ledgerEntriesProvider.overrideWith((ref, id) async => const []),
  ];
}

Widget _buildCard(
  SanctionQueueItemView item, {
  SanctionActionNotifier? notifier,
  String? contractName = 'Test Contract',
}) {
  final n = notifier ?? _MockSanctionActionNotifier();
  return ProviderScope(
    overrides: _baseOverrides(
      item: item,
      notifier: n,
      contractName: contractName,
    ),
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SanctionVerdictCard(item: item)),
      ),
    ),
  );
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('SanctionVerdictCard — Render', () {
    testWidgets('renders fine amount and clause badge', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.text('R\$ 1.500,00'), findsOneWidget);
      expect(find.text('ATR-01'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('shows SELAR and RECUSAR buttons for pending status', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.text('SELAR VEREDITO'), findsOneWidget);
      expect(find.text('RECUSAR VEREDITO'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — INV-4 Money Precision', () {
    testWidgets('renders BigInt cents with symmetric BRL formatting', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      // 199999 cents → R$ 1.999,99 (no rounding drift)
      await tester.pumpWidget(_buildCard(_makeItem(fineCents: 199999)));
      await tester.pump();
      expect(find.text('R\$ 1.999,99'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('formats million-cent fine without overflow', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      // 100000000 cents → R$ 1.000.000,00
      await tester.pumpWidget(_buildCard(_makeItem(fineCents: 100000000)));
      await tester.pump();
      expect(find.text('R\$ 1.000.000,00'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — INV-7 Immutability (SELADO)', () {
    testWidgets('shows SELADO badge when status is applied', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.applied)),
      );
      await tester.pump();

      expect(find.text('SELADO'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('shows SELADO badge when status is rejected', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.rejected)),
      );
      await tester.pump();

      expect(find.text('SELADO'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('hides action row when sealed (opacity 0.6)', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.applied)),
      );
      await tester.pump();

      expect(find.text('SELAR VEREDITO'), findsNothing);
      expect(find.text('RECUSAR VEREDITO'), findsNothing);
      expect(find.text('SOLICITAR PROVA FORENSE'), findsNothing);

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, closeTo(0.6, 0.001));

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — API Fail Fallbacks', () {
    testWidgets('renders fallback contract prefix when contractName is null', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem(), contractName: null));
      await tester.pump();

      expect(find.textContaining('CONTRACT'), findsWidgets);
      expect(find.text('R\$ 1.500,00'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('renders safely when geofence fields are null', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(
          _makeItem(
            geofenceCenterLat: null,
            geofenceCenterLng: null,
            geofenceRadiusMeters: null,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('R\$ 1.500,00'), findsOneWidget);
      expect(tester.takeException(), isNull);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — Confidence Double Confirmation', () {
    testWidgets(
      'shows AlertDialog on SELAR when confidence score < 70 and Cancelar blocks approve',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;

        final notifier = _MockSanctionActionNotifier();
        await tester.pumpWidget(
          _buildCard(_makeItem(confidenceScore: 50), notifier: notifier),
        );
        await tester.pump();

        await tester.tap(find.text('SELAR VEREDITO'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('Integridade Baixa'), findsOneWidget);
        expect(find.text('Confirmar Selamento'), findsOneWidget);

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(notifier.approveCalls, 0);

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets('boundary: score == 69 triggers dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem(confidenceScore: 69)));
      await tester.pump();

      await tester.tap(find.text('SELAR VEREDITO'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('boundary: score == 70 does NOT trigger dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final notifier = _MockSanctionActionNotifier();
      await tester.pumpWidget(
        _buildCard(_makeItem(confidenceScore: 70), notifier: notifier),
      );
      await tester.pump();

      await tester.tap(find.text('SELAR VEREDITO'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(notifier.approveCalls, 1);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('does NOT show AlertDialog on SELAR when confidence >= 70', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final notifier = _MockSanctionActionNotifier();
      await tester.pumpWidget(
        _buildCard(_makeItem(confidenceScore: 95), notifier: notifier),
      );
      await tester.pump();

      await tester.tap(find.text('SELAR VEREDITO'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(notifier.approveCalls, 1);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — WS-5 Map Sync', () {
    testWidgets('tap on card updates selectedSanctionFocusProvider', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final item = _makeItem();
      final notifier = _MockSanctionActionNotifier();
      final container = ProviderContainer(
        overrides: _baseOverrides(item: item, notifier: notifier),
      );
      addTearDown(container.dispose);

      expect(container.read(selectedSanctionFocusProvider), isNull);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SanctionVerdictCard(item: item),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap on the clause badge (outside InkWell/button regions).
      await tester.tap(find.text('ATR-01'));
      await tester.pump();

      final focus = container.read(selectedSanctionFocusProvider);
      expect(focus, isNotNull);
      expect(focus!.sanctionId, item.id);
      expect(focus.infractionPoint.latitude, closeTo(-23.5, 0.0001));
      expect(focus.infractionPoint.longitude, closeTo(-46.6, 0.0001));

      // Tap again → toggles off
      await tester.tap(find.text('ATR-01'));
      await tester.pump();
      expect(container.read(selectedSanctionFocusProvider), isNull);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — Audit: Reject Justification', () {
    testWidgets('tapping RECUSAR reveals rejection reason field', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('RECUSAR VEREDITO'));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('CONFIRMAR RECUSA disabled when reason < 10 chars', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      await tester.tap(find.text('RECUSAR VEREDITO'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'short');
      await tester.pump();

      final btnFinder = find.ancestor(
        of: find.text('CONFIRMAR RECUSA'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      final btn = tester.widget<FilledButton>(btnFinder.first);
      expect(btn.onPressed, isNull);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('CONFIRMAR RECUSA enabled when reason >= 10 chars', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final notifier = _MockSanctionActionNotifier();
      await tester.pumpWidget(_buildCard(_makeItem(), notifier: notifier));
      await tester.pump();

      await tester.tap(find.text('RECUSAR VEREDITO'));
      await tester.pump();

      await tester.enterText(
        find.byType(TextField),
        'Justificativa forense detalhada',
      );
      await tester.pump();

      final btnFinder = find.ancestor(
        of: find.text('CONFIRMAR RECUSA'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      final btn = tester.widget<FilledButton>(btnFinder.first);
      expect(btn.onPressed, isNotNull);

      await tester.tap(btnFinder.first);
      await tester.pump();
      expect(notifier.rejectCalls, 1);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — Forensic Seal (INV-9/INV-21)', () {
    testWidgets('renders SHA-256 hash prefix in seal row', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final item = _makeItem();
      await tester.pumpWidget(_buildCard(item));
      await tester.pump();

      expect(
        find.textContaining('SHA-256: ${item.shortEvidenceHash}'),
        findsOneWidget,
      );
      expect(find.text('Cadeia de Custódia · Prova Forense'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('tapping seal row opens InvestigationModal (audit trail)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.byType(InvestigationModal), findsNothing);

      await tester.tap(find.text('Cadeia de Custódia · Prova Forense'));
      await tester.pumpAndSettle();

      expect(find.byType(InvestigationModal), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — INV-7 Parity (disputed)', () {
    testWidgets('disputed status locks the card same as applied', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.disputed)),
      );
      await tester.pump();

      expect(find.text('SELADO'), findsOneWidget);
      expect(find.text('SELAR VEREDITO'), findsNothing);
      expect(find.text('RECUSAR VEREDITO'), findsNothing);

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, closeTo(0.6, 0.001));

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — Async State Visibility (INV-10)', () {
    testWidgets('loading state disables SELAR with spinner', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(), notifier: _LoadingActionNotifier()),
      );
      await tester.pump();

      final btnFinder = find.ancestor(
        of: find.text('SELAR VEREDITO'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      final btn = tester.widget<FilledButton>(btnFinder.first);
      expect(btn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('error state surfaces error banner', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(), notifier: _ErrorActionNotifier()),
      );
      await tester.pump();

      expect(find.textContaining('mock approve failure'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — A11Y Semantics', () {
    testWidgets('exposes fine semantics label for CFO screen readers', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(
        find.bySemanticsLabel(RegExp(r'Multa: R\$ 1\.500,00')),
        findsOneWidget,
      );

      addTearDown(tester.view.resetPhysicalSize);
    });
  });
}
