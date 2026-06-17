import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/forensic_evidence_modal.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
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
  int verifyCalls = 0;

  _MockSnapshotRepo({this.mockSnapshot, this.shouldThrowIntegrity = false});

  @override
  Future<EvidenceVerification> verify({
    required String organizationId,
    required String ledgerEntryId,
  }) async {
    verifyCalls++;
    if (shouldThrowIntegrity) {
      throw const IntegrityException(
        'Integrity check failed: tampered content',
        field: 'integrity_hash',
      );
    }
    if (mockSnapshot == null) {
      throw Exception('Not found');
    }
    return EvidenceVerification(
      ledgerEntryId: ledgerEntryId,
      status: EvidenceVerificationStatus.authentic,
      storedHash: mockSnapshot!.integrityHash,
      computedHash: mockSnapshot!.integrityHash,
      snapshot: mockSnapshot!,
    );
  }

  @override
  Future<EvidenceVerification> verifyByQueueEntry({
    required String organizationId,
    required String queueEntryId,
  }) async {
    verifyCalls++;
    if (shouldThrowIntegrity) {
      throw const IntegrityException(
        'Integrity check failed: tampered content',
        field: 'integrity_hash',
      );
    }
    if (mockSnapshot == null) {
      throw Exception('Not found');
    }
    return EvidenceVerification(
      ledgerEntryId: mockSnapshot!.ledgerEntryId,
      status: EvidenceVerificationStatus.authentic,
      storedHash: mockSnapshot!.integrityHash,
      computedHash: mockSnapshot!.integrityHash,
      snapshot: mockSnapshot!,
    );
  }

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
        {
          'rule_id': 'rule-gap',
          'rule_type': 'MAX_EVIDENCE_GAP',
          'rule_config': {'max_gap_seconds': 300},
          'rule_version': 1,
          'evaluation_order': 1,
        },
      ],
    },
  });
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  Widget buildModal({
    required ForensicEvidenceSnapshotRepository repository,
    required SecurityIncidentLogger securityLogger,
  }) {
    return ProviderScope(
      overrides: [
        currentOrganizationIdProvider.overrideWithValue('org-001'),
        forensicEvidenceSnapshotRepositoryProvider.overrideWithValue(
          repository,
        ),
        securityIncidentLoggerProvider.overrideWithValue(securityLogger),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ForensicEvidenceModal(queueEntryId: 'queue-001'),
        ),
      ),
    );
  }

  group('ForensicEvidenceModal TDD', () {
    testWidgets('renders loading state initially', (tester) async {
      final repo = _MockSnapshotRepo(mockSnapshot: _makeMockSnapshot());
      final logger = _MockSecurityIncidentLogger();

      await tester.pumpWidget(
        buildModal(repository: repo, securityLogger: logger),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'renders authentic snapshot details correctly (Green Badge & Timezone Display)',
      (tester) async {
        final snapshot = _makeMockSnapshot();
        final repo = _MockSnapshotRepo(mockSnapshot: snapshot);
        final logger = _MockSecurityIncidentLogger();

        await tester.pumpWidget(
          buildModal(repository: repo, securityLogger: logger),
        );
        await tester.pumpAndSettle();

        // Green confidence seal badge
        expect(find.text('Cópia Autenticada'), findsOneWidget);
        expect(find.byIcon(Icons.verified_user), findsOneWidget);

        // Verify human parameters
        expect(find.text('Tolerância Máxima de Atraso'), findsOneWidget);
        expect(find.text('15 minutos'), findsOneWidget);
        expect(find.text('Intervalo Máximo de Evidência'), findsOneWidget);
        expect(find.text('300 segundos'), findsOneWidget);

        // Verify read-only formatting (no edit/save buttons or TextFields)
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Salvar'), findsNothing);
        expect(find.text('Editar'), findsNothing);

        // Verify date display contains timezone info
        final localSealed = snapshot.sealedAtUtc.toLocal();
        expect(find.textContaining(localSealed.timeZoneName), findsWidgets);
      },
    );

    testWidgets(
      'renders tampered state on IntegrityException (Red Alert, blocked rules, silent log)',
      (tester) async {
        final repo = _MockSnapshotRepo(shouldThrowIntegrity: true);
        final logger = _MockSecurityIncidentLogger();

        await tester.pumpWidget(
          buildModal(repository: repo, securityLogger: logger),
        );
        await tester.pumpAndSettle();

        // Red critical warning alert
        expect(
          find.textContaining('Divergência Crítica de Integridade'),
          findsOneWidget,
        );
        expect(find.textContaining('Suspeita de Fraude'), findsOneWidget);

        // Check blocked reading of rules
        expect(find.text('Tolerância Máxima de Atraso'), findsNothing);

        // Verify immediate silent security log for tampering
        expect(
          logger.loggedEvents.contains('FORENSIC_INTEGRITY_COMPROMISED'),
          isTrue,
        );

        // Incident Escalation button must be present
        expect(find.text('ESCALAR INCIDENTE'), findsOneWidget);

        // Click escalation button
        await tester.tap(find.text('ESCALAR INCIDENTE'));
        await tester.pump();

        // Verify security escalation incident logged
        expect(
          logger.loggedEvents.contains(
            'SECURITY_INCIDENT_ESCALATION_REQUESTED',
          ),
          isTrue,
        );
      },
    );
  });
}
