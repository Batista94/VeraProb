import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';

Map<String, dynamic> _baseRow({
  String id = 'fes-1',
  String orgId = 'org-1',
  String hash = 'abc123',
}) => {
  'id': id,
  'organization_id': orgId,
  'ledger_entry_id': 'ledger-1',
  'contract_id': 'contract-1',
  'rule_set_id': 'rs-1',
  'sla_rule_version': 2,
  'schema_version': 1,
  'effective_from_utc': null,
  'effective_to_utc': null,
  'snapshot': <String, dynamic>{'rules': <dynamic>[]},
  'integrity_hash': hash,
  'sealed_by': 'user-1',
  'sealed_at_utc': '2026-08-01T12:00:00Z',
};

void main() {
  group('EvidenceVerificationStatus', () {
    test('authentic and tampered are distinct', () {
      expect(
        EvidenceVerificationStatus.authentic,
        isNot(EvidenceVerificationStatus.tampered),
      );
    });
  });

  group('EvidenceVerification', () {
    late ForensicEvidenceSnapshot snapshot;

    setUp(() {
      snapshot = ForensicEvidenceSnapshot.fromJson(_baseRow());
    });

    test('isAuthentic true when status is authentic', () {
      final v = EvidenceVerification(
        ledgerEntryId: 'ledger-1',
        status: EvidenceVerificationStatus.authentic,
        storedHash: 'abc',
        computedHash: 'abc',
        snapshot: snapshot,
      );
      expect(v.isAuthentic, isTrue);
    });

    test('isAuthentic false when status is tampered', () {
      final v = EvidenceVerification(
        ledgerEntryId: 'ledger-1',
        status: EvidenceVerificationStatus.tampered,
        storedHash: 'abc',
        computedHash: 'xyz',
        snapshot: snapshot,
      );
      expect(v.isAuthentic, isFalse);
    });

    test('captures ledgerEntryId, hashes, and snapshot', () {
      const stored = 'stored-hash';
      const computed = 'computed-hash';

      final v = EvidenceVerification(
        ledgerEntryId: 'ledger-99',
        status: EvidenceVerificationStatus.tampered,
        storedHash: stored,
        computedHash: computed,
        snapshot: snapshot,
      );

      expect(v.ledgerEntryId, 'ledger-99');
      expect(v.storedHash, stored);
      expect(v.computedHash, computed);
      expect(v.snapshot, snapshot);
    });
  });
}
