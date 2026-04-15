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
import 'package:veraprob/state/providers/shared_providers.dart';

import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/approve_sanction_handler.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_handler.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/services/rbac_service.dart';

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

class _MockApproveHandler extends ApproveSanctionHandler {
  _MockApproveHandler()
    : super(
        tenantValidator: _MockTenantValidationService(),
        queueRepo: _MockQueueRepo(),
        ledger: _MockLedgerRepo(),
        rbac: RbacService(),
        dateTimeProvider: _MockDateTimeProvider(DateTime.now().toUtc()),
      );
}

class _MockRejectHandler extends RejectSanctionHandler {
  _MockRejectHandler()
    : super(
        tenantValidator: _MockTenantValidationService(),
        queueRepo: _MockQueueRepo(),
        ledger: _MockLedgerRepo(),
        rbac: RbacService(),
        clock: _MockDateTimeProvider(DateTime.now().toUtc()),
      );
}

class _MockSanctionActionNotifier extends SanctionActionNotifier {
  _MockSanctionActionNotifier()
    : super(
        approveHandler: _MockApproveHandler(),
        rejectHandler: _MockRejectHandler(),
      );

  @override
  AsyncValue<void> get state => const AsyncData(null);
}

SanctionQueueItemView _makeItem() {
  final evidence = VerdictEvidence.create(
    clauseRef: 'ATR-01',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5,
    primaryEvidenceLng: -46.6,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 1, 15, 10, 0),
    deltaValue: 5.0,
    thresholdValue: 0.0,
    fineCents: const Money(150000),
    confidenceScore: 95,
  );
  return SanctionQueueItemView(
    id: 'test-id-001',
    organizationId: 'org-001',
    ledgerEntryId: 'ledger-001',
    setId: 'set-001',
    contractId: 'contract-001',
    verdictEvidence: evidence,
    status: SanctionReviewStatus.pending,
    createdAtUtc: DateTime.utc(2026, 1, 15, 10, 0),
  );
}

Widget _buildCard(SanctionQueueItemView item) {
  return ProviderScope(
    overrides: [
      contractNameProvider.overrideWith((ref, id) async => 'Test Contract'),
      pendingSanctionsStreamProvider.overrideWith(
        (ref) => Stream.value([item]),
      ),
      sanctionWindowProvider.overrideWith((ref, setId) async => null),
      // Fix: Override providers that depend on Supabase initialization
      sanctionActionStateProvider.overrideWith(
        (ref, id) => _MockSanctionActionNotifier(),
      ),
      tenantValidationServiceProvider.overrideWithValue(
        _MockTenantValidationService(),
      ),
      currentOperatorIdProvider.overrideWithValue('test-user'),
      currentOperatorEmailProvider.overrideWithValue('test@example.com'),
      currentSessionIdProvider.overrideWithValue('test-session'),
      dateTimeProviderProvider.overrideWithValue(
        _MockDateTimeProvider(DateTime.utc(2026, 1, 15)),
      ),
      vehicleInfractionRecurrenceProvider.overrideWith(
        (ref, key) async => null,
      ),
    ],
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

  group('SanctionVerdictCard', () {
    testWidgets('renders fine amount and clause badge', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.text('R\$ 1.500,00'), findsOneWidget);
      expect(find.text('ATR-01'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('shows VALIDAR and REJEITAR buttons', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.text('SELAR VEREDITO'), findsOneWidget);
      expect(find.text('RECUSAR VEREDITO'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('tapping REJEITAR reveals rejection reason field', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      // Rejection field should not be visible before tap
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('RECUSAR VEREDITO'));
      await tester.pump();

      // Rejection reason text field appears after tap
      expect(find.byType(TextField), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });
}
