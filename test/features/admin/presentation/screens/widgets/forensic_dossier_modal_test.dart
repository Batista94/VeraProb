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
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart'
    as attach;
import 'package:veraprob/state/providers/dispute_evidence_providers.dart';

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
    List<attach.DisputeEvidenceAttachment> evidenceList = const [],
    ForensicDossierTab initialTab = ForensicDossierTab.evidence,
    VerdictProvenance? provenance,
  }) {
    return ProviderScope(
      overrides: [
        currentOrganizationIdProvider.overrideWithValue('org-001'),
        forensicEvidenceSnapshotRepositoryProvider.overrideWithValue(
          repository,
        ),
        verdictProvenanceProvider.overrideWith((ref, id) async => provenance),
        securityIncidentLoggerProvider.overrideWithValue(logger),
        evaluationTracesProvider.overrideWith((ref, id) async => traces),
        disputeEvidenceListProvider.overrideWith(
          (ref, id) async => evidenceList,
        ),
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

  group('ForensicDossierModal — Evidência tab (manifest + telemetry)', () {
    testWidgets('surfaces actual vs limit speed and the excess in Section B', (
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

    testWidgets('shows empty state when no telemetry exists in Section B', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildModal(
          repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
          logger: _MockSecurityIncidentLogger(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sem telemetria'), findsOneWidget);
    });

    testWidgets(
      'shows attachment manifest with verification badges in Section A',
      (tester) async {
        final mockAttachment = attach.DisputeEvidenceAttachment.validated(
          id: 'att-001',
          organizationId: 'org-001',
          queueEntryId: 'queue-001',
          storagePath: 'path/to/evidence.pdf',
          fileName: 'evidence.pdf',
          mimeType: 'application/pdf',
          fileSizeBytes: 2048576, // ~2.0 MB
          sha256Hash:
              'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e',
          verificationStatus: attach.EvidenceVerificationStatus.verified,
          hashVerifiedAtUtc: DateTime.utc(2026, 1, 15, 12, 5),
          uploadedBy: 'carrier-user-123',
          attachedAtUtc: DateTime.utc(2026, 1, 15, 12, 0),
          deletedAtUtc: null,
        );

        await tester.pumpWidget(
          buildModal(
            repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
            logger: _MockSecurityIncidentLogger(),
            evidenceList: [mockAttachment],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('evidence.pdf'), findsOneWidget);
        expect(find.text('VERIFICADO'), findsOneWidget);
        expect(find.textContaining('2.0 MB'), findsOneWidget);
        expect(
          find.textContaining(
            'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows empty state when no attachments exist in Section A', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildModal(
          repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
          logger: _MockSecurityIncidentLogger(),
          evidenceList: [],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhuma evidência anexada pela transportadora.'),
        findsOneWidget,
      );
    });
  });

  group('ForensicDossierModal — Custódia tab', () {
    testWidgets(
      'authentic snapshot surfaces actor email when provenance exists',
      (tester) async {
        await tester.pumpWidget(
          buildModal(
            repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
            logger: _MockSecurityIncidentLogger(),
            initialTab: ForensicDossierTab.custody,
            provenance: (
              actorEmail: 'auditor@tenant.com',
              actorUserId: 'user-001',
              sealedAtUtc: DateTime.utc(2026, 1, 15, 15),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cópia Autenticada'), findsOneWidget);
        expect(find.text('Selado Por'), findsOneWidget);
        expect(find.text('auditor@tenant.com'), findsOneWidget);
        // Ensure the UUID is not in the main text tree
        expect(find.text('operator-123'), findsNothing);
        expect(
          find.textContaining('sha256-mock-hash-value-1234567890abcdef'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'authentic snapshot degrades to short UUID when email missing',
      (tester) async {
        await tester.pumpWidget(
          buildModal(
            repository: _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot()),
            logger: _MockSecurityIncidentLogger(),
            initialTab: ForensicDossierTab.custody,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cópia Autenticada'), findsOneWidget);
        expect(find.text('Selado Por (Operador)'), findsOneWidget);
        expect(find.text('operator-123...'), findsOneWidget); // truncated
      },
    );

    testWidgets('SHA-256 is tap-to-copy and shows success SnackBar', (
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

      await tester.ensureVisible(find.byType(IconButton).last);
      await tester.tap(find.byType(IconButton).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Hash copiado para a área de transferência'),
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
