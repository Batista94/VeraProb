import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';

void main() {
  final now = DateTime.utc(2024, 6, 1, 12, 0, 0);

  VerdictEvidence makeEvidence(int fineCents) => VerdictEvidence.create(
    clauseRef: 'VEL-01',
    ruleId: 'rule-speed-v1',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5505,
    primaryEvidenceLng: -46.6333,
    primaryEvidenceTimestampUtc: now,
    deltaValue: 8.5,
    thresholdValue: 80.0,
    fineCents: Money(fineCents),
    confidenceScore: 99,
  );

  SanctionQueueItemView makeView({int fineCents = 150000}) =>
      SanctionQueueItemView(
        id: 'sq-1',
        organizationId: 'org-1',
        ledgerEntryId: 'ledger-1',
        setId: 'set-1',
        contractId: 'contract-1',
        verdictEvidence: makeEvidence(fineCents),
        status: SanctionReviewStatus.pending,
        createdAtUtc: now,
      );

  group('SanctionQueueItemView', () {
    group('formattedFine', () {
      test('formats R\$ 1.500,00 correctly', () {
        final view = makeView(fineCents: 150000);
        expect(view.formattedFine, 'R\$ 1.500,00');
      });

      test('formats R\$ 500,00 (no thousands separator)', () {
        final view = makeView(fineCents: 50000);
        expect(view.formattedFine, 'R\$ 500,00');
      });

      test('formats R\$ 10.000,00', () {
        final view = makeView(fineCents: 1000000);
        expect(view.formattedFine, 'R\$ 10.000,00');
      });

      test('formats R\$ 1.500,50', () {
        final view = makeView(fineCents: 150050);
        expect(view.formattedFine, 'R\$ 1.500,50');
      });
    });

    test('shortEvidenceHash returns first 12 characters', () {
      final view = makeView();
      expect(view.shortEvidenceHash.length, 12);
      expect(
        view.shortEvidenceHash,
        view.verdictEvidence.evidenceHash.substring(0, 12),
      );
    });

    test('formattedConfidence includes percentage sign', () {
      final view = makeView();
      expect(view.formattedConfidence, '99%');
    });

    test('fromEntry maps all fields correctly', () {
      final entry = SanctionReviewQueueEntry(
        id: 'sq-1',
        organizationId: 'org-1',
        ledgerEntryId: 'ledger-1',
        setId: 'set-1',
        contractId: 'contract-1',
        verdictEvidence: makeEvidence(150000),
        status: SanctionReviewStatus.pending,
        createdAtUtc: now,
        reviewedAtUtc: null,
        reviewedByUserId: null,
        rejectionReason: null,
      );
      final view = SanctionQueueItemView.fromEntry(entry);
      expect(view.id, entry.id);
      expect(view.organizationId, entry.organizationId);
      expect(view.setId, entry.setId);
      expect(view.contractId, entry.contractId);
      expect(view.status, entry.status);
      expect(view.reviewedAtUtc, isNull);
      expect(view.rejectionReason, isNull);
      expect(view.contractName, isNull);
    });

    test('fromRow parses all required fields', () {
      final evidence = makeEvidence(150000);
      final row = {
        'id': 'sq-row-1',
        'organization_id': 'org-1',
        'ledger_entry_id': 'ledger-1',
        'set_id': 'set-1',
        'contract_id': 'contract-1',
        'verdict_evidence': evidence.toJson(),
        'status': 'pending',
        'created_at': now.toIso8601String(),
        'reviewed_at': null,
        'reviewed_by': null,
        'rejection_reason': null,
      };
      final view = SanctionQueueItemView.fromRow(row);
      expect(view.id, 'sq-row-1');
      expect(view.organizationId, 'org-1');
      expect(view.status, SanctionReviewStatus.pending);
      expect(view.reviewedAtUtc, isNull);
      // Absent asset/operator columns degrade gracefully to null (INV-14).
      expect(view.vehiclePlate, isNull);
      expect(view.operatorName, isNull);
      expect(view.assetIdentifier, isNull);
    });

    test('fromRow parses asset (plate) and operator name (INV-14)', () {
      final evidence = makeEvidence(150000);
      final row = {
        'id': 'sq-row-asset',
        'organization_id': 'org-1',
        'ledger_entry_id': 'ledger-asset',
        'set_id': 'set-asset',
        'contract_id': 'contract-asset',
        'verdict_evidence': evidence.toJson(),
        'status': 'pending',
        'created_at': now.toIso8601String(),
        'reviewed_at': null,
        'reviewed_by': null,
        'rejection_reason': null,
        'vehicle_plate': 'TST-0001',
        'operator_name': 'João Silva',
      };
      final view = SanctionQueueItemView.fromRow(row);
      expect(view.vehiclePlate, 'TST-0001');
      expect(view.assetIdentifier, 'TST-0001');
      expect(view.operatorName, 'João Silva');
    });

    test('fromRow with reviewed fields', () {
      final evidence = makeEvidence(150000);
      final reviewed = now.add(const Duration(hours: 1));
      final row = {
        'id': 'sq-row-2',
        'organization_id': 'org-1',
        'ledger_entry_id': 'ledger-2',
        'set_id': 'set-2',
        'contract_id': 'contract-2',
        'verdict_evidence': evidence.toJson(),
        'status': 'applied',
        'created_at': now.toIso8601String(),
        'reviewed_at': reviewed.toIso8601String(),
        'reviewed_by': 'user-audit-1',
        'rejection_reason': null,
      };
      final view = SanctionQueueItemView.fromRow(row);
      expect(view.status, SanctionReviewStatus.applied);
      expect(view.reviewedAtUtc, isNotNull);
      expect(view.reviewedByUserId, 'user-audit-1');
    });
  });
}
