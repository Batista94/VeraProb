import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/reporting/generate_forensic_dossier_handler.dart';
import 'package:veraprob/state/providers/reporting_providers.dart';
import 'package:veraprob/application/dispute_portal/portal_submission_audit_gateway.dart';
import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/application/sla_audit/resolve_dispute_command.dart'
    show DisputeResolution;
import 'package:veraprob/state/providers/dispute_portal_providers.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/features/admin/presentation/widgets/sanction_verdict_card.dart';
import 'package:veraprob/features/admin/presentation/widgets/sentence_panel_modal.dart';
import 'package:veraprob/features/admin/presentation/shared/widgets/reverse_geocoded_address.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/forensic_dossier_modal.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/dispute_portal_token_providers.dart';
import 'package:veraprob/state/providers/dispute_reason_code_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sanction_focus_provider.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/state/providers/investigation_providers.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';

import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';

class _FakeGenerateForensicDossierHandler extends Fake
    implements GenerateForensicDossierHandler {
  @override
  Future<List<int>> handle(GenerateForensicDossierCommand command) async {
    return [1, 2, 3, 4];
  }
}

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

final _fixedUtc = DateTime.utc(2026, 1, 15, 12, 0);

/// Minimal grouped catalogue for the reason-code dropdown (Componente 4.2):
/// one named TECHNICAL code + OTHER, keeping the test menu short/deterministic.
const _testReasonCodes = <DisputeReasonCode>[
  DisputeReasonCode(
    code: 'SENSOR_FAULT',
    category: 'TECHNICAL',
    labelPt: 'Falha de Sensor',
    labelEn: 'Sensor Fault',
    isActive: true,
  ),
  DisputeReasonCode(
    code: 'OTHER',
    category: 'OTHER',
    labelPt: 'Outro (ver comentário)',
    labelEn: 'Other',
    isActive: true,
  ),
];

class _MockPortalTokenNotifier extends DisputePortalTokenNotifier {
  _MockPortalTokenNotifier() : super('test-id-001');

  int generateCalls = 0;

  @override
  AsyncValue<String?> build() => const AsyncData(null);

  @override
  Future<String?> generate({
    required String createdByUserId,
    required String actorEmail,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    generateCalls++;
    state = const AsyncData('tok-abc-123');
    return 'tok-abc-123';
  }
}

class _LoadingActionNotifier extends SanctionActionNotifier {
  _LoadingActionNotifier() : super('test-id');

  @override
  AsyncValue<void> build() => const AsyncLoading();
}

class _ErrorActionNotifier extends SanctionActionNotifier {
  _ErrorActionNotifier() : super('test-id');

  @override
  AsyncValue<void> build() => const AsyncError(
    IntegrityException('Falha simulada ao selar o veredito'),
    StackTrace.empty,
  );
}

/// Simulates a transport/domain failure surfaced by the guarded notifier:
/// `resolveDispute` resolves to `AsyncError` (never throws), exactly like the
/// real `guardedAction`. The card must rethrow it so the SentencePanelModal
/// stays open and keeps the auditor's input.
class _FailingDisputeNotifier extends SanctionActionNotifier {
  _FailingDisputeNotifier() : super('test-id');

  @override
  Future<void> resolveDispute({
    required String queueEntryId,
    required DisputeResolution resolution,
    required String resolvedByUserId,
    required String actorEmail,
    String? resolutionReason,
    String? reasonCode,
    List<String> evidenceIds = const [],
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    state = const AsyncError(
      IntegrityException('Conexão perdida durante o envio'),
      StackTrace.empty,
    );
  }
}

class _MockSanctionActionNotifier extends SanctionActionNotifier {
  _MockSanctionActionNotifier() : super('test-id');

  int approveCalls = 0;
  int rejectCalls = 0;
  int resolveDisputeCalls = 0;
  DisputeResolution? lastResolution;
  String? lastResolutionReason;
  String? lastReasonCode;
  String? lastApproveReasonCode;
  String? lastApproveReviewerReason;

  @override
  Future<void> resolveDispute({
    required String queueEntryId,
    required DisputeResolution resolution,
    required String resolvedByUserId,
    required String actorEmail,
    String? resolutionReason,
    String? reasonCode,
    List<String> evidenceIds = const [],
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    resolveDisputeCalls++;
    lastResolution = resolution;
    lastResolutionReason = resolutionReason;
    lastReasonCode = reasonCode;
    state = const AsyncData(null);
  }

  @override
  Future<void> approve({
    required String queueEntryId,
    required String approvedByUserId,
    required String actorEmail,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
    String? reasonCode,
    String? reviewerReason,
  }) async {
    approveCalls++;
    lastApproveReasonCode = reasonCode;
    lastApproveReviewerReason = reviewerReason;
    state = const AsyncData(null);
  }

  String? lastRejectReasonCode;

  @override
  Future<void> reject({
    required String queueEntryId,
    required String rejectedByUserId,
    required String actorEmail,
    required String rejectionReason,
    required String reasonCode,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    rejectCalls++;
    lastRejectReasonCode = reasonCode;
    state = const AsyncData(null);
  }
}

/// Audit gateway whose `listPending` returns empty on the FIRST call and a
/// single finalized submission on every subsequent call — lets a test prove a
/// realtime tick triggered a re-fetch (call #2) that surfaces the contraprova.
class _CountingAuditGateway implements PortalSubmissionAuditGateway {
  int listCalls = 0;

  @override
  Future<List<PortalSubmissionSummary>> listPending({
    required String organizationId,
    required String queueEntryId,
  }) async {
    listCalls++;
    if (listCalls == 1) return const [];
    return [
      PortalSubmissionSummary(
        submissionId: 'sub-1',
        attachmentId: 'att-1',
        fileName: 'contraprova.jpg',
        mimeTypeDetected: 'image/jpeg',
        fileSizeBytesActual: 2048,
        sha256Server: 'a' * 64,
        justificationText: 'Contestacao com anexo.',
        status: 'PENDING_AUDIT',
        submittedAtUtc: DateTime.utc(2026, 6, 1),
        finalizedAtUtc: DateTime.utc(2026, 6, 1),
      ),
    ];
  }

  @override
  Future<List<PortalJustificationSummary>> listPendingJustifications({
    required String organizationId,
    required String queueEntryId,
  }) async => const [];
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
  String clauseRef = 'ATR-01',
  double deltaValue = 5.0,
  double thresholdValue = 0.0,
  String? vehiclePlate = 'TST-0001',
  String? operatorName = 'João Silva',
  String? rejectionReason,
  DateTime? resolutionDueAtUtc,
  DateTime? disputedAtUtc,
  String? disputedBy,
  String? reviewedByUserId,
  DateTime? reviewedAtUtc,
  String? firstReviewerId,
}) {
  final evidence = VerdictEvidence.create(
    clauseRef: clauseRef,
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5,
    primaryEvidenceLng: -46.6,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 1, 15, 10, 0),
    deltaValue: deltaValue,
    thresholdValue: thresholdValue,
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
    vehiclePlate: vehiclePlate,
    operatorName: operatorName,
    rejectionReason: rejectionReason,
    resolutionDueAtUtc: resolutionDueAtUtc,
    disputedAtUtc: disputedAtUtc,
    disputedBy: disputedBy,
    reviewedByUserId: reviewedByUserId,
    reviewedAtUtc: reviewedAtUtc,
    firstReviewerId: firstReviewerId,
  );
}

List<Override> _baseOverrides({
  required SanctionQueueItemView item,
  required SanctionActionNotifier notifier,
  String? contractName = 'Test Contract',
  String? currentOperatorId = 'test-user',
  Stream<Map<String, int>>? portalEvidenceStream,
}) {
  return [
    // PKG3: deterministic realtime tick. Default = empty (never emits) so cards
    // outside the realtime test never hit the unoverridden SupabaseClient.
    portalEvidenceRealtimeProvider.overrideWith(
      (ref) => portalEvidenceStream ?? const Stream<Map<String, int>>.empty(),
    ),
    contractNameProvider.overrideWith((ref, id) async => contractName),
    pendingSanctionsStreamProvider.overrideWith((ref) => Stream.value([item])),
    sanctionWindowProvider.overrideWith((ref, setId) async => null),
    disputeReasonCodesProvider.overrideWith((ref) async => _testReasonCodes),
    disputeRetractionProvenanceProvider.overrideWith((ref, id) async => null),
    sanctionActionStateProvider.overrideWith2((_) => notifier),
    tenantValidationServiceProvider.overrideWithValue(
      _MockTenantValidationService(),
    ),
    currentOperatorIdProvider.overrideWithValue(currentOperatorId),
    currentOperatorEmailProvider.overrideWithValue('test@example.com'),
    currentSessionIdProvider.overrideWithValue('test-session'),
    dateTimeProviderProvider.overrideWithValue(
      _MockDateTimeProvider(_fixedUtc),
    ),
    vehicleInfractionRecurrenceProvider.overrideWith((ref, key) async => null),
    evaluationTracesProvider.overrideWith((ref, id) async => const []),
    ledgerEntriesProvider.overrideWith((ref, id) async => const []),
    // Deterministic: bypass the live Nominatim call for the infraction address.
    reverseGeocodeProvider.overrideWith((ref, _) async => null),
    generateForensicDossierHandlerProvider.overrideWithValue(
      _FakeGenerateForensicDossierHandler(),
    ),
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

/// Opens the dispute reason-code dropdown and selects the entry with [labelPt].
Future<void> _selectReasonCode(WidgetTester tester, String labelPt) async {
  await tester.tap(find.byKey(const ValueKey('dispute-reason-code-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(labelPt).last);
  await tester.pumpAndSettle();
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

    testWidgets('shows CONFIRMAR and ANULAR buttons for pending status', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.text('CONFIRMAR INFRAÇÃO'), findsOneWidget);
      expect(find.text('ANULAR INFRAÇÃO'), findsOneWidget);

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
    testWidgets('shows MULTA APLICADA badge when status is applied', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.applied)),
      );
      await tester.pump();

      expect(find.text('MULTA APLICADA'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('shows VEREDITO RECUSADO badge when status is rejected', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.rejected)),
      );
      await tester.pump();

      expect(find.text('VEREDITO RECUSADO'), findsOneWidget);
      expect(find.text('SELADO'), findsNothing);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('hides action row when sealed (opacity 0.6)', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.applied)),
      );
      await tester.pump();

      expect(find.text('CONFIRMAR INFRAÇÃO'), findsNothing);
      expect(find.text('ANULAR INFRAÇÃO'), findsNothing);
      expect(find.text('SOLICITAR DEFESA'), findsNothing);

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, closeTo(0.6, 0.001));

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets(
      'rejected card shows Dossiê Forense button (INV-21 regression guard)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          _buildCard(_makeItem(status: SanctionReviewStatus.rejected)),
        );
        await tester.pump();

        expect(find.text('Dossiê Forense'), findsOneWidget);

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
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

        await tester.tap(find.text('CONFIRMAR INFRAÇÃO'));
        await tester.pumpAndSettle();

        await _selectReasonCode(tester, 'Falha de Sensor');
        await tester.tap(
          find.descendant(
            of: find.byType(SentencePanelModal),
            matching: find.text('CONFIRMAR INFRAÇÃO'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('Integridade Baixa'), findsOneWidget);
        expect(find.text('Confirmar Selamento'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Cancelar'),
          ),
        );
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

      await tester.tap(find.text('CONFIRMAR INFRAÇÃO'));
      await tester.pumpAndSettle();

      await _selectReasonCode(tester, 'Falha de Sensor');
      await tester.tap(
        find.descendant(
          of: find.byType(SentencePanelModal),
          matching: find.text('CONFIRMAR INFRAÇÃO'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancelar'),
        ),
      );
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

      await tester.tap(find.text('CONFIRMAR INFRAÇÃO'));
      await tester.pumpAndSettle();

      await _selectReasonCode(tester, 'Falha de Sensor');
      await tester.tap(
        find.descendant(
          of: find.byType(SentencePanelModal),
          matching: find.text('CONFIRMAR INFRAÇÃO'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(notifier.approveCalls, 1);
      // Reason code is now threaded into approve (persisted server-side), not
      // discarded.
      expect(notifier.lastApproveReasonCode, 'SENSOR_FAULT');

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

      await tester.tap(find.text('CONFIRMAR INFRAÇÃO'));
      await tester.pumpAndSettle();

      await _selectReasonCode(tester, 'Falha de Sensor');
      await tester.tap(
        find.descendant(
          of: find.byType(SentencePanelModal),
          matching: find.text('CONFIRMAR INFRAÇÃO'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(notifier.approveCalls, 1);
      // Reason code is now threaded into approve (persisted server-side), not
      // discarded.
      expect(notifier.lastApproveReasonCode, 'SENSOR_FAULT');

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

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(item: item, notifier: notifier),
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

      final container = tester.container();
      expect(container.read(selectedSanctionFocusProvider), isNull);

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

    testWidgets(
      'tapping address re-centers every time (selectionEpoch increments)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;

        final item = _makeItem();
        await tester.pumpWidget(
          ProviderScope(
            overrides: _baseOverrides(
              item: item,
              notifier: _MockSanctionActionNotifier(),
            ),
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

        final container = tester.container();
        final address = find.byType(ReverseGeocodedAddress);
        expect(address, findsOneWidget);

        // First tap: focus set, epoch = 1.
        await tester.tap(address);
        await tester.pump();
        final first = container.read(selectedSanctionFocusProvider);
        expect(first, isNotNull);
        expect(first!.sanctionId, item.id);
        expect(first.selectionEpoch, 1);

        // Re-tap the SAME (already-focused) address: must re-emit a distinct
        // event so the map re-frames — epoch increments, sanction unchanged.
        await tester.tap(address);
        await tester.pump();
        final second = container.read(selectedSanctionFocusProvider);
        expect(second!.sanctionId, item.id);
        expect(second.selectionEpoch, 2);

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });

  group('SanctionVerdictCard — Audit: Reject Justification', () {
    testWidgets('tapping RECUSAR reveals reason-code dropdown + note field', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('dispute-reason-code-dropdown')),
        findsNothing,
      );

      await tester.tap(find.text('ANULAR INFRAÇÃO'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('dispute-reason-code-dropdown')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsWidgets);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('CONFIRMAR RECUSA disabled without a reason code (BUG-01)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      await tester.tap(find.text('ANULAR INFRAÇÃO'));
      await tester.pumpAndSettle();

      FilledButton confirmBtn() => tester.widget<FilledButton>(
        find
            .descendant(
              of: find.byType(SentencePanelModal),
              matching: find.byType(FilledButton),
            )
            .first,
      );

      await tester.enterText(
        find.byKey(const ValueKey('sentence-comment-field')),
        'Justificativa forense detalhada',
      );
      await tester.pump();
      expect(confirmBtn().onPressed, isNull);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('CONFIRMAR RECUSA disabled when note < 10 chars', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      await tester.tap(find.text('ANULAR INFRAÇÃO'));
      await tester.pumpAndSettle();

      await _selectReasonCode(tester, 'Falha de Sensor');
      await tester.enterText(
        find.byKey(const ValueKey('sentence-comment-field')),
        'short',
      );
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find
            .descendant(
              of: find.byType(SentencePanelModal),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(btn.onPressed, isNull);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('CONFIRMAR RECUSA enabled with code + note >= 10 chars', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final notifier = _MockSanctionActionNotifier();
      await tester.pumpWidget(_buildCard(_makeItem(), notifier: notifier));
      await tester.pump();

      await tester.tap(find.text('ANULAR INFRAÇÃO'));
      await tester.pumpAndSettle();

      await _selectReasonCode(tester, 'Falha de Sensor');
      await tester.enterText(
        find.byKey(const ValueKey('sentence-comment-field')),
        'Justificativa forense detalhada',
      );
      await tester.pump();

      final btnFinder = find.descendant(
        of: find.byType(SentencePanelModal),
        matching: find.byType(FilledButton),
      );
      final btn = tester.widget<FilledButton>(btnFinder.first);
      expect(btn.onPressed, isNotNull);

      await tester.tap(btnFinder.first);
      await tester.pumpAndSettle();
      expect(notifier.rejectCalls, 1);
      expect(notifier.lastRejectReasonCode, 'SENSOR_FAULT');

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  _resolutionSealAndA11yTests();

  _sealedEvidenceAndStyleTests();

  _portalRealtimeTests();
}

void _portalRealtimeTests() {
  group('SanctionVerdictCard — Portal evidence realtime refresh (PKG3)', () {
    testWidgets('new attachment tick re-fetches the pending submissions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final item = _makeItem(status: SanctionReviewStatus.disputed);
      final controller = StreamController<Map<String, int>>.broadcast();
      addTearDown(controller.close);
      final gateway = _CountingAuditGateway();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(
              item: item,
              notifier: _MockSanctionActionNotifier(),
              portalEvidenceStream: controller.stream,
            ),
            portalSubmissionAuditGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SanctionVerdictCard(item: item),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // listPending #1 → empty → the contraprova zone stays hidden.
      expect(gateway.listCalls, 1);
      expect(find.textContaining('EVIDÊNCIAS DA DEFESA'), findsNothing);

      // Baseline realtime snapshot (no attachments yet), then a NEW attachment
      // for THIS dispute → count 0→1 must invalidate + re-fetch.
      controller.add(const {});
      await tester.pump();
      controller.add({item.id: 1});
      await tester.pumpAndSettle();

      expect(gateway.listCalls, 2);
      expect(find.textContaining('EVIDÊNCIAS DA DEFESA'), findsOneWidget);
      expect(find.text('contraprova.jpg'), findsOneWidget);
    });

    testWidgets(
      'surfaced contraprova shows the carrier testimony + thumbnail',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final item = _makeItem(status: SanctionReviewStatus.disputed);
        final controller = StreamController<Map<String, int>>.broadcast();
        addTearDown(controller.close);
        final gateway = _CountingAuditGateway();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ..._baseOverrides(
                item: item,
                notifier: _MockSanctionActionNotifier(),
                portalEvidenceStream: controller.stream,
              ),
              portalSubmissionAuditGatewayProvider.overrideWithValue(gateway),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SanctionVerdictCard(item: item),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        controller.add(const {});
        await tester.pump();
        controller.add({item.id: 1});
        await tester.pumpAndSettle();

        // Bug 1a fix: the auditor now reads the justification text...
        // (AnimatedCrossFade keeps both collapsed/expanded children mounted.)
        expect(find.text('JUSTIFICATIVA DA CONTESTAÇÃO'), findsOneWidget);
        expect(find.textContaining('Contestacao com anexo.'), findsWidgets);
        // ...and a viewable attachment thumbnail (proxied image) is present.
        expect(find.byType(CachedNetworkImage), findsWidgets);
      },
    );

    testWidgets('tick for a DIFFERENT dispute does not re-fetch', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final item = _makeItem(status: SanctionReviewStatus.disputed);
      final controller = StreamController<Map<String, int>>.broadcast();
      addTearDown(controller.close);
      final gateway = _CountingAuditGateway();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(
              item: item,
              notifier: _MockSanctionActionNotifier(),
              portalEvidenceStream: controller.stream,
            ),
            portalSubmissionAuditGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SanctionVerdictCard(item: item),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.listCalls, 1);

      controller.add(const {});
      await tester.pump();
      // Attachment for an unrelated queue entry → this card must NOT re-fetch.
      controller.add({'unrelated-queue-id': 1});
      await tester.pumpAndSettle();

      expect(gateway.listCalls, 1);
      expect(find.textContaining('EVIDÊNCIAS DA DEFESA'), findsNothing);
    });
  });
}

void _resolutionSealAndA11yTests() {
  group('SanctionVerdictCard — Forensic Seal (INV-9/INV-21)', () {
    testWidgets('renders SHA-256 hash in seal row passively', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final item = _makeItem();
      await tester.pumpWidget(_buildCard(item));
      await tester.pump();

      expect(
        find.textContaining('SHA-256: ${item.shortEvidenceHash}'),
        findsOneWidget,
      );

      // Verify bottom padding on the card's scroll view to prevent collisions/overlaps
      final scrollView = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(SanctionVerdictCard),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(scrollView.padding, const EdgeInsets.only(bottom: 16));

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — Dispute Resolution (Pacote 3)', () {
    testWidgets('disputed is interactive: 3 resolution actions, full opacity', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.disputed)),
      );
      await tester.pump();

      expect(find.text('AGUARDANDO EVIDÊNCIA'), findsOneWidget);
      expect(find.text('ANULAR INFRAÇÃO'), findsOneWidget);
      expect(find.text('CONFIRMAR INFRAÇÃO'), findsOneWidget);
      expect(find.text('Cancelar solicitação'), findsOneWidget);
      // BUG-02: the auditor can mint a carrier portal link from a disputed card.
      expect(find.text('GERAR LINK DE DISPUTA'), findsOneWidget);
      // Pending-only control must NOT leak into a disputed card.
      expect(find.text('SOLICITAR DEFESA'), findsNothing);

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, closeTo(1.0, 0.001));

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets(
      'ANULAR MULTA: confirm requires reason code AND a mandatory comment (5.4)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;

        final notifier = _MockSanctionActionNotifier();
        await tester.pumpWidget(
          _buildCard(
            _makeItem(status: SanctionReviewStatus.disputed),
            notifier: notifier,
          ),
        );
        await tester.pump();

        // Reveal the reason-code dropdown + mandatory comment field.
        await tester.tap(find.text('ANULAR INFRAÇÃO'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('dispute-reason-code-dropdown')),
          findsOneWidget,
        );

        FilledButton inhibitBtn() => tester.widget<FilledButton>(
          find
              .descendant(
                of: find.byType(SentencePanelModal),
                matching: find.byType(FilledButton),
              )
              .first,
        );

        // No code, no comment → disabled.
        expect(inhibitBtn().onPressed, isNull);

        // A named code ALONE is NOT enough — forgiving a fine demands prose.
        await _selectReasonCode(tester, 'Falha de Sensor');
        expect(inhibitBtn().onPressed, isNull);

        // Comment < 10 chars → still disabled.
        await tester.enterText(
          find.byKey(const ValueKey('sentence-comment-field')),
          'curto',
        );
        await tester.pump();
        expect(inhibitBtn().onPressed, isNull);

        // Named code + comment >= 10 → enabled; fires accept with code + prose.
        await tester.enterText(
          find.byKey(const ValueKey('sentence-comment-field')),
          'Sensor com falha comprovada em laudo.',
        );
        await tester.pump();
        expect(inhibitBtn().onPressed, isNotNull);

        await tester.tap(
          find
              .descendant(
                of: find.byType(SentencePanelModal),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(notifier.resolveDisputeCalls, 1);
        expect(notifier.lastResolution, DisputeResolution.accept);
        expect(notifier.lastReasonCode, 'SENSOR_FAULT');
        expect(
          notifier.lastResolutionReason,
          'Sensor com falha comprovada em laudo.',
        );

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      'MANTER MULTA: OTHER code reveals free-text gated at 10 chars',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;

        final notifier = _MockSanctionActionNotifier();
        await tester.pumpWidget(
          _buildCard(
            _makeItem(status: SanctionReviewStatus.disputed),
            notifier: notifier,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('CONFIRMAR INFRAÇÃO'));
        await tester.pumpAndSettle();

        await _selectReasonCode(tester, 'Outro (ver comentário)');

        // Free-text field now present (in addition to the dropdown's field).
        final freeText = find.byKey(const ValueKey('sentence-comment-field'));
        FilledButton affirmBtn() => tester.widget<FilledButton>(
          find
              .descendant(
                of: find.byType(SentencePanelModal),
                matching: find.byType(FilledButton),
              )
              .first,
        );

        // < 10 chars → disabled.
        await tester.enterText(freeText, 'curto');
        await tester.pump();
        expect(affirmBtn().onPressed, isNull);

        // >= 10 chars → enabled, fires overturn with OTHER + description.
        await tester.enterText(freeText, 'Descrição detalhada do motivo.');
        await tester.pump();
        expect(affirmBtn().onPressed, isNotNull);

        await tester.tap(
          find
              .descendant(
                of: find.byType(SentencePanelModal),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(notifier.resolveDisputeCalls, 1);
        expect(notifier.lastResolution, DisputeResolution.overturn);
        expect(notifier.lastReasonCode, 'OTHER');
        expect(notifier.lastResolutionReason, 'Descrição detalhada do motivo.');

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      'MANTER MULTA: named code fires overturn without a comment; seals hash cue',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;

        final notifier = _MockSanctionActionNotifier();
        await tester.pumpWidget(
          _buildCard(
            _makeItem(status: SanctionReviewStatus.disputed),
            notifier: notifier,
          ),
        );
        await tester.pump();

        // Hash-seal cue is hidden until the affirm arc is opened.
        expect(find.textContaining('sela o hash'), findsNothing);

        await tester.tap(find.text('CONFIRMAR INFRAÇÃO'));
        await tester.pumpAndSettle();

        // 5.4: affirming surfaces the immutable-seal cue (INV-21).
        expect(find.textContaining('sela o hash'), findsOneWidget);

        // Named code alone enables affirm — the sealed hash is the evidence.
        await _selectReasonCode(tester, 'Falha de Sensor');

        await tester.tap(
          find
              .descendant(
                of: find.byType(SentencePanelModal),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        await tester.pumpAndSettle();

        expect(notifier.resolveDisputeCalls, 1);
        expect(notifier.lastResolution, DisputeResolution.overturn);
        expect(notifier.lastReasonCode, 'SENSOR_FAULT');
        expect(notifier.lastResolutionReason, isNull);

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets('CANCELAR SOLICITAÇÃO retracts with no reason, no field', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final notifier = _MockSanctionActionNotifier();
      await tester.pumpWidget(
        _buildCard(
          _makeItem(status: SanctionReviewStatus.disputed),
          notifier: notifier,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Cancelar solicitação'));
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
      expect(notifier.resolveDisputeCalls, 1);
      expect(notifier.lastResolution, DisputeResolution.retract);
      expect(notifier.lastResolutionReason, isNull);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets(
      'GERAR LINK DE DISPUTA mints a token and shows a copyable URL (BUG-02)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;

        final item = _makeItem(status: SanctionReviewStatus.disputed);
        final portal = _MockPortalTokenNotifier();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ..._baseOverrides(
                item: item,
                notifier: _MockSanctionActionNotifier(),
              ),
              disputePortalTokenProvider.overrideWith2((_) => portal),
            ],
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

        // URL is hidden until a token is minted.
        expect(find.byKey(const ValueKey('dispute-portal-url')), findsNothing);

        await tester.tap(find.text('GERAR LINK DE DISPUTA'));
        await tester.pump();

        expect(portal.generateCalls, 1);
        final url = find.byKey(const ValueKey('dispute-portal-url'));
        expect(url, findsOneWidget);
        expect(
          tester.widget<SelectableText>(url).data,
          contains('/portal/dispute?token=tok-abc-123'),
        );

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      'BUG-03: tall disputed card scrolls so action buttons stay reachable',
      (tester) async {
        // A short viewport that the card content exceeds. Before the fix the
        // action row fell below the fold with no way to reach it.
        tester.view.physicalSize = const Size(420, 600);
        tester.view.devicePixelRatio = 1.0;

        final item = _makeItem(status: SanctionReviewStatus.disputed);
        await tester.pumpWidget(
          ProviderScope(
            overrides: _baseOverrides(
              item: item,
              notifier: _MockSanctionActionNotifier(),
            ),
            child: MaterialApp(
              home: Scaffold(body: SanctionVerdictCard(item: item)),
            ),
          ),
        );
        await tester.pump();

        // The action buttons exist in the tree and can be scrolled into view via
        // the card's internal SingleChildScrollView — no off-screen exception.
        final action = find.text('CONFIRMAR INFRAÇÃO');
        expect(action, findsOneWidget);
        await tester.ensureVisible(action);
        await tester.pump();
        expect(tester.takeException(), isNull);

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      'submit failure keeps SentencePanelModal open and preserves input',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;

        final notifier = _FailingDisputeNotifier();
        await tester.pumpWidget(
          _buildCard(
            _makeItem(status: SanctionReviewStatus.disputed),
            notifier: notifier,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('ANULAR INFRAÇÃO'));
        await tester.pumpAndSettle();

        await _selectReasonCode(tester, 'Falha de Sensor');
        const comment = 'Laudo técnico em anexo comprova a falha do sensor.';
        await tester.enterText(
          find.byKey(const ValueKey('sentence-comment-field')),
          comment,
        );
        await tester.pump();

        await tester.tap(
          find
              .descendant(
                of: find.byType(SentencePanelModal),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        await tester.pumpAndSettle();

        // Transactional submit: the modal must NOT close on failure.
        expect(find.byType(SentencePanelModal), findsOneWidget);
        // Clean domain error rendered inside the modal (Lesson 5 — no prefix).
        expect(
          find.descendant(
            of: find.byType(SentencePanelModal),
            matching: find.textContaining('Conexão perdida durante o envio'),
          ),
          findsOneWidget,
        );
        // The auditor's typed comment survives for an immediate retry.
        expect(find.text(comment), findsOneWidget);

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
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
        of: find.text('CONFIRMAR INFRAÇÃO'),
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

      // Clean domain message — never a raw `toString()` prefix (Lesson 5).
      expect(
        find.textContaining('Falha simulada ao selar o veredito'),
        findsOneWidget,
      );
      expect(find.textContaining('IntegrityException'), findsNothing);

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

void _sealedEvidenceAndStyleTests() {
  group('SanctionVerdictCard — Forensic Dossier Export', () {
    testWidgets(
      'renders download dossier button, handles click and displays success SnackBar',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;

        final item = _makeItem(status: SanctionReviewStatus.pending);
        await tester.pumpWidget(_buildCard(item));
        await tester.pump();

        // Find the button by key
        final buttonFinder = find.byKey(
          const ValueKey('download-dossier-button'),
        );
        expect(buttonFinder, findsOneWidget);

        // Verify the styling: it must be wrapped in a Container with width/height of 40px
        final container = tester.widget<Container>(
          find
              .descendant(of: buttonFinder, matching: find.byType(Container))
              .first,
        );
        expect(container.constraints?.minWidth, 40.0);
        expect(container.constraints?.minHeight, 40.0);

        // Assert the dossier button is correctly positioned in the Financial Hero zone,
        // specifically next to the confidence badge (INTEGRIDADE) within the same Row.
        final confidenceText = find.text('INTEGRIDADE');
        expect(confidenceText, findsOneWidget);
        final siblingRow = find.ancestor(
          of: buttonFinder,
          matching: find.byWidgetPredicate((widget) {
            return widget is Row &&
                widget.mainAxisSize == MainAxisSize.min &&
                find
                    .descendant(
                      of: find.byWidget(widget),
                      matching: confidenceText,
                    )
                    .evaluate()
                    .isNotEmpty;
          }),
        );
        expect(siblingRow, findsOneWidget);

        // Mock BinaryMessenger call handler for FileSaver package to avoid MissingPluginException
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('file_saver'),
          (methodCall) async => 'fake_file_path.pdf',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => Directory.systemTemp.path,
        );

        // Tap the download button
        await tester.runAsync(() async {
          await tester.tap(buttonFinder);
          // Wait for the real file I/O to complete in the event loop
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump(); // Allow SnackBar to build

        // SnackBar must display success message
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.textContaining('Dossiê preliminar baixado'),
          findsOneWidget,
        );

        // Clean up temp files from temp directory
        try {
          final tempDir = Directory.systemTemp;
          for (final entity in tempDir.listSync()) {
            if (entity is File && entity.path.contains('dossie_preliminar_')) {
              await entity.delete();
            }
          }
        } catch (_) {}

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });

  group('SanctionVerdictCard — Sealed Evidence Action Button', () {
    testWidgets(
      'renders Dossiê Forense when status is applied and opens the dossier modal',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;

        final item = _makeItem(status: SanctionReviewStatus.applied);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ..._baseOverrides(
                item: item,
                notifier: _MockSanctionActionNotifier(),
              ),
              forensicEvidenceSnapshotRepositoryProvider.overrideWithValue(
                _MockSnapshotRepo(),
              ),
              securityIncidentLoggerProvider.overrideWithValue(
                _MockSecurityIncidentLogger(),
              ),
            ],
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

        final btn = find.text('Dossiê Forense');
        expect(btn, findsOneWidget);

        await tester.tap(btn);
        await tester.pumpAndSettle();

        expect(find.byType(ForensicDossierModal), findsOneWidget);

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });

  group('SanctionVerdictCard — Severity accent (status-driven)', () {
    Color accentColor(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('verdict-severity-accent')),
      );
      return (box.decoration as BoxDecoration).color!;
    }

    testWidgets('pending keeps red accent even when focused', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      // Unfocused pending → red.
      expect(accentColor(tester), VeraProbColors.error);

      // Focus the card by tapping its clause badge.
      await tester.tap(find.text('ATR-01'));
      await tester.pump();

      // Still red — focus must not override severity.
      expect(accentColor(tester), VeraProbColors.error);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('disputed → amber accent; applied → red accent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.disputed)),
      );
      await tester.pump();
      expect(accentColor(tester), VeraProbColors.warning);

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.applied)),
      );
      await tester.pump();
      expect(accentColor(tester), VeraProbColors.error);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets(
      'rejected → neutral slate accent (no directional bias, INV-23)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          _buildCard(_makeItem(status: SanctionReviewStatus.rejected)),
        );
        await tester.pump();
        expect(
          accentColor(tester),
          VeraProbColors.neutral.withValues(alpha: 0.5),
        );

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      'focused card border matches the severity accent, never a contrasting hue',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;

        final item = _makeItem(status: SanctionReviewStatus.disputed);
        await tester.pumpWidget(
          ProviderScope(
            overrides: _baseOverrides(
              item: item,
              notifier: _MockSanctionActionNotifier(),
            ),
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

        Color outerBorderColor() {
          final container = tester.widget<AnimatedContainer>(
            find.byType(AnimatedContainer).first,
          );
          return (container.decoration as BoxDecoration).border!.top.color;
        }

        // Focus the card (WS-5 map sync) by tapping its clause badge.
        await tester.tap(find.text('ATR-01'));
        await tester.pump();

        // The full border must adopt the SAME severity color as the left accent
        // (amber for disputed) — not the teal `primary` (the green-around-orange
        // regression).
        expect(outerBorderColor(), VeraProbColors.warning);
        expect(outerBorderColor(), accentColor(tester));
        expect(outerBorderColor(), isNot(VeraProbColors.primary));

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });

  group('SanctionVerdictCard — Asset/Operator identity (INV-14)', () {
    testWidgets('renders vehicle plate and operator name prominently', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(
          _makeItem(vehiclePlate: 'TST-0001', operatorName: 'Ana Reis'),
        ),
      );
      await tester.pump();

      expect(find.text('TST-0001'), findsOneWidget);
      expect(find.text('Ana Reis'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('null operator degrades to "Não Identificado"', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(vehiclePlate: 'TST-0001', operatorName: null)),
      );
      await tester.pump();

      expect(find.text('Não Identificado'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('SELAR disabled when vehicle plate is missing', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final notifier = _MockSanctionActionNotifier();
      await tester.pumpWidget(
        _buildCard(_makeItem(vehiclePlate: null), notifier: notifier),
      );
      await tester.pump();

      final btnFinder = find.ancestor(
        of: find.text('CONFIRMAR INFRAÇÃO'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      final btn = tester.widget<FilledButton>(btnFinder.first);
      expect(btn.onPressed, isNull);

      // Tapping must not invoke approve.
      await tester.tap(find.text('CONFIRMAR INFRAÇÃO'), warnIfMissed: false);
      await tester.pump();
      expect(notifier.approveCalls, 0);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('SELAR enabled when vehicle plate is present', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final notifier = _MockSanctionActionNotifier();
      await tester.pumpWidget(
        _buildCard(_makeItem(vehiclePlate: 'TST-0001'), notifier: notifier),
      );
      await tester.pump();

      final btnFinder = find.ancestor(
        of: find.text('CONFIRMAR INFRAÇÃO'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      final btn = tester.widget<FilledButton>(btnFinder.first);
      expect(btn.onPressed, isNotNull);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — VEL layout', () {
    testWidgets('renders speed raw details for VEL clauses', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      final velItem = _makeItem(
        id: 'test-vel-01',
        clauseRef: 'VEL-01',
        thresholdValue: 80.0,
        deltaValue: 5.0,
      );

      await tester.pumpWidget(_buildCard(velItem));
      await tester.pump();

      expect(find.text('VELOCIDADE REGISTRADA'), findsOneWidget);
      expect(find.text('LIMITE CONTRATUAL'), findsOneWidget);
      expect(find.text('EXCESSO'), findsOneWidget);
      expect(
        find.text('85.0'),
        findsOneWidget,
      ); // limit + delta = 80.0 + 5.0 = 85.0 (rendered separately from unit)
      expect(find.text('80.0 km/h'), findsOneWidget); // limit
      expect(find.text('+5.0 km/h'), findsOneWidget); // excess

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — Dispute SLA chip (Componente 4.2c)', () {
    testWidgets('overdue deadline renders VENCIDA chip', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;

      final due = DateTime.now().toUtc().subtract(const Duration(days: 1));
      await tester.pumpWidget(
        _buildCard(
          _makeItem(
            status: SanctionReviewStatus.disputed,
            resolutionDueAtUtc: due,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('SLA VENCIDA'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('future deadline renders restantes chip', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;

      final due = DateTime.now().toUtc().add(const Duration(days: 5));
      await tester.pumpWidget(
        _buildCard(
          _makeItem(
            status: SanctionReviewStatus.disputed,
            resolutionDueAtUtc: due,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('restantes'), findsOneWidget);
      expect(find.textContaining('SLA VENCIDA'), findsNothing);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('disputed without deadline shows no chip', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.disputed)),
      );
      await tester.pump();

      expect(find.textContaining('SLA'), findsNothing);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('SanctionVerdictCard — Retraction provenance (INV-23)', () {
    testWidgets('pending item previously disputed surfaces RETRATADA trail', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildCard(
          _makeItem(
            status: SanctionReviewStatus.pending,
            disputedAtUtc: DateTime.utc(2026, 1, 14, 9, 0),
            disputedBy: 'auditor-7',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('SOLICITAÇÃO RETRATADA'), findsOneWidget);
      expect(find.textContaining('Aberta por'), findsOneWidget);
      expect(find.textContaining('Cancelada por'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('plain pending item shows no retraction trail', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.text('SOLICITAÇÃO RETRATADA'), findsNothing);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  // ── C1: Suspect A regression — null operatorId guard ──────────────────────

  group(
    'SanctionVerdictCard — Baixar Dossiê null operatorId guard (Suspect A)',
    () {
      testWidgets(
        'C1: null currentOperatorIdProvider shows "Sessão expirada" — handler not called',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1200);
          tester.view.devicePixelRatio = 1.0;

          // Rejected status reproduces the exact bug scenario:
          // admin annuls → card moves to "Concluídos" → clicks "Baixar Dossiê"
          // while auth state might be briefly null after navigation.
          final item = _makeItem(status: SanctionReviewStatus.rejected);
          final notifier = _MockSanctionActionNotifier();

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                // Suspect A: simulate auth null (e.g. brief refresh during navigation).
                ..._baseOverrides(
                  item: item,
                  notifier: notifier,
                  currentOperatorId: null,
                ),
              ],
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

          final buttonFinder = find.byKey(
            const ValueKey('download-dossier-button'),
          );
          expect(buttonFinder, findsOneWidget);

          await tester.tap(buttonFinder);
          await tester.pump();

          // Guard must fire — no handler invocation, no SnackBar success.
          expect(find.byType(SnackBar), findsNothing);
          expect(find.textContaining('Sessão expirada'), findsOneWidget);

          addTearDown(tester.view.resetPhysicalSize);
        },
      );
    },
  );

  // ── Pkg 1: Morality-free action buttons ──────────────────────────────────
  // Semantic color (green/red) is reserved for STATE (badges). Verbs MUST be
  // neutral so confirming a fine never reads as "the good choice". These guards
  // pin the neutralized palette so a future restyle can't silently moralize the
  // actions again.
  group('SanctionVerdictCard — morality-free action palette', () {
    Future<void> pumpPending(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _buildCard(_makeItem(status: SanctionReviewStatus.pending)),
      );
      await tester.pump();
    }

    testWidgets(
      'pending CONFIRMAR INFRAÇÃO — FilledButton with verdictAction (INV-23)',
      (tester) async {
        await pumpPending(tester);

        final btn = tester.widget<FilledButton>(
          find
              .ancestor(
                of: find.text('CONFIRMAR INFRAÇÃO'),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        const states = <WidgetState>{};
        expect(
          btn.style?.backgroundColor?.resolve(states),
          VeraProbColors.verdictAction,
        );
        expect(btn.style?.foregroundColor?.resolve(states), Colors.white);
      },
    );

    testWidgets(
      'pending ANULAR INFRAÇÃO — FilledButton with verdictAction, parity with CONFIRMAR (INV-23)',
      (tester) async {
        await pumpPending(tester);

        final btn = tester.widget<FilledButton>(
          find
              .ancestor(
                of: find.text('ANULAR INFRAÇÃO'),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        const states = <WidgetState>{};
        expect(
          btn.style?.backgroundColor?.resolve(states),
          VeraProbColors.verdictAction,
        );
        expect(btn.style?.foregroundColor?.resolve(states), Colors.white);
      },
    );

    testWidgets(
      'pending SOLICITAR DEFESA — muted OutlinedButton, not info-blue (INV-23)',
      (tester) async {
        await pumpPending(tester);

        final btn = tester.widget<OutlinedButton>(
          find
              .ancestor(
                of: find.text('SOLICITAR DEFESA'),
                matching: find.byType(OutlinedButton),
              )
              .first,
        );
        const states = <WidgetState>{};
        expect(
          btn.style?.foregroundColor?.resolve(states),
          VeraProbColors.textSecondary,
        );
        expect(btn.style?.side?.resolve(states)?.color, VeraProbColors.border);
      },
    );

    testWidgets(
      'disputed ANULAR INFRAÇÃO — FilledButton with verdictAction (INV-23)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildCard(_makeItem(status: SanctionReviewStatus.disputed)),
        );
        await tester.pump();

        // Find the ANULAR button specifically in disputed context
        // (two ANULAR candidates if pending was visible; here only disputed)
        final btn = tester.widget<FilledButton>(
          find
              .ancestor(
                of: find.text('ANULAR INFRAÇÃO'),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        expect(
          btn.style?.backgroundColor?.resolve(const <WidgetState>{}),
          VeraProbColors.verdictAction,
        );
      },
    );

    testWidgets(
      'disputed CONFIRMAR INFRAÇÃO — FilledButton with verdictAction (INV-23)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildCard(_makeItem(status: SanctionReviewStatus.disputed)),
        );
        await tester.pump();

        final btn = tester.widget<FilledButton>(
          find
              .ancestor(
                of: find.text('CONFIRMAR INFRAÇÃO'),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        expect(
          btn.style?.backgroundColor?.resolve(const <WidgetState>{}),
          VeraProbColors.verdictAction,
        );
      },
    );

    testWidgets(
      'fine amount — pending uses textPrimary, applied uses error, rejected uses textDisabled + strikethrough (INV-23)',
      (tester) async {
        Text fineText(WidgetTester t) =>
            t.widget<Text>(find.text('R\$ 1.500,00').first);

        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // pending → textPrimary, no strikethrough
        await tester.pumpWidget(
          _buildCard(_makeItem(status: SanctionReviewStatus.pending)),
        );
        await tester.pump();
        expect(fineText(tester).style?.color, VeraProbColors.textPrimary);
        expect(
          fineText(tester).style?.decoration,
          isNot(TextDecoration.lineThrough),
        );

        // applied → error (penalty confirmed)
        await tester.pumpWidget(
          _buildCard(_makeItem(status: SanctionReviewStatus.applied)),
        );
        await tester.pump();
        expect(fineText(tester).style?.color, VeraProbColors.error);

        // rejected → textDisabled + strikethrough
        await tester.pumpWidget(
          _buildCard(_makeItem(status: SanctionReviewStatus.rejected)),
        );
        await tester.pump();
        expect(fineText(tester).style?.color, VeraProbColors.textDisabled);
        expect(fineText(tester).style?.decoration, TextDecoration.lineThrough);
      },
    );

    testWidgets(
      'peer review CONFIRMAR (2º AUDITOR) — FilledButton with verdictAction, not success (INV-23)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildCard(_makeItem(status: SanctionReviewStatus.pendingPeerReview)),
        );
        await tester.pump();

        final btn = tester.widget<FilledButton>(
          find
              .ancestor(
                of: find.text('CONFIRMAR (2º AUDITOR)'),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        const states = <WidgetState>{};
        expect(
          btn.style?.backgroundColor?.resolve(states),
          VeraProbColors.verdictAction,
        );
        expect(btn.style?.foregroundColor?.resolve(states), Colors.white);
      },
    );
  });
}

// ── Test Mock Definitions for Forensic Evidence Modal ─────────────────────────

class _MockSnapshotRepo implements ForensicEvidenceSnapshotRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSecurityIncidentLogger extends SecurityIncidentLogger {
  _MockSecurityIncidentLogger() : super(null);
}
