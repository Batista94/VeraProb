import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';
import 'package:veraprob/domain/sla_audit/evidence_payload.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/forensic_dossier_modal.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/investigation_providers.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

class _MockSecurityIncidentLogger extends SecurityIncidentLogger {
  _MockSecurityIncidentLogger() : super(null);

  final List<String> loggedEvents = [];

  @override
  Future<void> log({
    required String eventType,
    required Map<String, dynamic> metadata,
    required Map<String, dynamic> jwtClaimsSnapshot,
  }) async {
    loggedEvents.add(eventType);
  }
}

class _MockSnapshotRepo implements ForensicEvidenceSnapshotRepository {
  final ForensicEvidenceSnapshot? mockSnapshot;
  final bool shouldThrowIntegrity;

  _MockSnapshotRepo({this.mockSnapshot, this.shouldThrowIntegrity = false});

  EvidenceVerification _verify(String ledgerEntryId) {
    if (shouldThrowIntegrity) {
      throw const IntegrityException(
        'Integrity check failed: tampered content',
        field: 'integrity_hash',
      );
    }
    if (mockSnapshot == null) throw Exception('Not found');
    return EvidenceVerification(
      ledgerEntryId: mockSnapshot!.ledgerEntryId,
      status: EvidenceVerificationStatus.authentic,
      storedHash: mockSnapshot!.integrityHash,
      computedHash: mockSnapshot!.integrityHash,
      snapshot: mockSnapshot!,
    );
  }

  @override
  Future<EvidenceVerification> verify({
    required String organizationId,
    required String ledgerEntryId,
  }) async => _verify(ledgerEntryId);

  @override
  Future<EvidenceVerification> verifyByQueueEntry({
    required String organizationId,
    required String queueEntryId,
  }) async => _verify(queueEntryId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ForensicEvidenceSnapshot _makeMockSnapshot() {
  return ForensicEvidenceSnapshot.fromJson({
    'id': 'fes-001',
    'organization_id': 'org-001',
    'ledger_entry_id': 'ledger-001',
    'contract_id': 'contract-001',
    'rule_set_id': 'set-001',
    'sla_rule_version': 2,
    'schema_version': 1,
    'effective_from_utc': '2026-01-15T12:00:00Z',
    'effective_to_utc': '2026-02-15T12:00:00Z',
    'sealed_by': 'operator-123',
    'sealed_at_utc': '2026-01-15T15:00:00Z',
    'integrity_hash': 'sha256-mock-hash-value-1234567890abcdef',
    'snapshot': {
      'rules': [
        {
          'rule_id': 'rule-delay',
          'rule_type': 'MAX_TOLERANCE_DELAY',
          'rule_config': {'threshold_minutes': 15},
          'rule_version': 1,
          'evaluation_order': 0,
        },
      ],
    },
  });
}

EvaluationTrace _speedTrace() {
  return EvaluationTrace(
    id: 'trace-001',
    organizationId: 'org-001',
    entityId: 'set-001',
    triggeringEventId: 'evt-001',
    evaluatedAtUtc: DateTime.utc(2026, 1, 15, 14),
    engineVersion: 'v1.0.0',
    decisions: const [
      EvaluationDecision(
        ruleId: 'rule-speed',
        ruleType: 'SPEED_LIMIT',
        ruleVersion: 1,
        rulePriority: 1,
        outcome: 'PENALTY_ASSESSED',
        evidence: SpeedViolationEvidence(
          actualSpeedKmh: 88.5,
          limitSpeedKmh: 80.0,
        ),
      ),
    ],
  );
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  Widget buildModal({
    required ForensicEvidenceSnapshotRepository repository,
    required SecurityIncidentLogger logger,
    List<EvaluationTrace> traces = const [],
    ForensicDossierTab initialTab = ForensicDossierTab.evidence,
  }) {
    return ProviderScope(
      overrides: [
        currentOrganizationIdProvider.overrideWithValue('org-001'),
        forensicEvidenceSnapshotRepositoryProvider.overrideWithValue(
          repository,
        ),
        securityIncidentLoggerProvider.overrideWithValue(logger),
        evaluationTracesProvider.overrideWith((ref, id) async => traces),
        ledgerEntriesProvider.overrideWith((ref, id) async => const []),
        executionStateProvider.overrideWith((ref, id) async => null),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ForensicDossierModal(
            setId: 'set-001',
            contractId: 'contract-001',
            queueEntryId: 'queue-001',
            initialTab: initialTab,
          ),
        ),
      ),
    );
  }

  group('ForensicDossierModal — structure', () {
    testWidgets('renders the four forensic tabs', (tester) async {
      await tester.pumpWidget(
        buildModal(
          repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
          logger: _MockSecurityIncidentLogger(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Tab, 'Evidência'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Cadeia de Custódia'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Decisões'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Regra'), findsOneWidget);
      expect(find.text('Dossiê Forense'), findsOneWidget);
    });
  });

  group('ForensicDossierModal — Evidência tab (raw telemetry)', () {
    testWidgets('surfaces actual vs limit speed and the excess', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildModal(
          repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
          logger: _MockSecurityIncidentLogger(),
          traces: [_speedTrace()],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('88.5 km/h'), findsOneWidget);
      expect(find.text('80.0 km/h'), findsOneWidget);
      expect(find.text('+8.5 km/h'), findsOneWidget);
    });

    testWidgets('shows empty state when no telemetry exists', (tester) async {
      await tester.pumpWidget(
        buildModal(
          repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
          logger: _MockSecurityIncidentLogger(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sem telemetria bruta registrada'), findsOneWidget);
    });
  });

  group('ForensicDossierModal — Custódia tab', () {
    testWidgets('authentic snapshot shows seal + operator + hash', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildModal(
          repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
          logger: _MockSecurityIncidentLogger(),
          initialTab: ForensicDossierTab.custody,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cópia Autenticada'), findsOneWidget);
      expect(find.text('operator-123'), findsOneWidget);
      expect(
        find.text('sha256-mock-hash-value-1234567890abcdef'),
        findsOneWidget,
      );
    });

    testWidgets(
      'tampered snapshot logs incident once, blocks read, escalates',
      (tester) async {
        final logger = _MockSecurityIncidentLogger();
        await tester.pumpWidget(
          buildModal(
            repository: _MockSnapshotRepo(shouldThrowIntegrity: true),
            logger: logger,
            initialTab: ForensicDossierTab.custody,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Divergência Crítica de Integridade'),
          findsOneWidget,
        );
        expect(
          logger.loggedEvents.contains('FORENSIC_INTEGRITY_COMPROMISED'),
          isTrue,
        );

        await tester.tap(find.text('ESCALAR INCIDENTE'));
        await tester.pump();

        expect(
          logger.loggedEvents.contains(
            'SECURITY_INCIDENT_ESCALATION_REQUESTED',
          ),
          isTrue,
        );
      },
    );
  });

  group('ForensicDossierModal — Regra tab', () {
    testWidgets('shows frozen rule parameters humanized', (tester) async {
      await tester.pumpWidget(
        buildModal(
          repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
          logger: _MockSecurityIncidentLogger(),
          initialTab: ForensicDossierTab.rule,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tolerância Máxima de Atraso'), findsOneWidget);
      expect(find.text('15 minutos'), findsOneWidget);
    });

    testWidgets('tampered blocks parameter read-out on Regra tab', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildModal(
          repository: _MockSnapshotRepo(shouldThrowIntegrity: true),
          logger: _MockSecurityIncidentLogger(),
          initialTab: ForensicDossierTab.rule,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tolerância Máxima de Atraso'), findsNothing);
      expect(find.textContaining('bloqueada de forma'), findsOneWidget);
    });
  });
}
