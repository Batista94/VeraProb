import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';

String _hex(String c) => List.filled(64, c).join();

Map<String, dynamic> _row({
  String organizationId = 'org-1',
  String? integrityHash,
}) {
  final snapshot = <String, dynamic>{
    'schema_version': 1,
    'organization_id': organizationId,
    'contract_id': 'contract-1',
    'rule_set_id': 'rs-1',
    'sla_rule_version': 3,
    'verdict_type': 'NO_SHOW_PENALTY',
    'occurred_at_utc': '2026-08-01T12:00:00+00:00',
    'rules': [
      {
        'rule_id': 'rule-2',
        'rule_type': 'NO_SHOW_PENALTY',
        'rule_config': {'multiplier_value': 2},
        'rule_version': 3,
        'evaluation_order': 1,
      },
      {
        'rule_id': 'rule-1',
        'rule_type': 'MAX_TOLERANCE_DELAY',
        'rule_config': {'threshold_minutes': 15},
        'rule_version': 2,
        'evaluation_order': 0,
      },
    ],
  };
  return {
    'id': 'fes-1',
    'organization_id': organizationId,
    'ledger_entry_id': 'ledger-1',
    'contract_id': 'contract-1',
    'rule_set_id': 'rs-1',
    'sla_rule_version': 3,
    'schema_version': 1,
    'effective_from_utc': '2026-07-01T00:00:00+00:00',
    'effective_to_utc': null,
    'snapshot': snapshot,
    'integrity_hash': integrityHash ?? _hex('a'),
    'sealed_by': 'user-9',
    'sealed_at_utc': '2026-08-01T12:00:00+00:00',
  };
}

void main() {
  group('ForensicEvidenceSnapshot', () {
    test('fromJson maps all fields and normalizes timestamps to UTC', () {
      final s = ForensicEvidenceSnapshot.fromJson(_row());

      expect(s.id, 'fes-1');
      expect(s.organizationId, 'org-1');
      expect(s.ledgerEntryId, 'ledger-1');
      expect(s.contractId, 'contract-1');
      expect(s.slaRuleVersion, 3);
      expect(s.schemaVersion, 1);
      expect(s.sealedBy, 'user-9');
      expect(s.sealedAtUtc.isUtc, isTrue);
      expect(s.effectiveFromUtc!.isUtc, isTrue);
      expect(s.effectiveToUtc, isNull);
    });

    test('toJson round-trips through fromJson preserving identity', () {
      final original = ForensicEvidenceSnapshot.fromJson(_row());
      final restored = ForensicEvidenceSnapshot.fromJson(original.toJson());
      expect(restored, original); // Equatable on id
      expect(restored.integrityHash, original.integrityHash);
    });

    test(
      'rules getter projects snake_case items ordered by evaluationOrder',
      () {
        final s = ForensicEvidenceSnapshot.fromJson(_row());
        final ordered = s.rules.orderedRules;

        expect(ordered.length, 2);
        expect(ordered.first.ruleType, SlaRuleType.maxToleranceDelay);
        expect(ordered.first.evaluationOrder, 0);
        expect(ordered.last.ruleType, SlaRuleType.noShowPenalty);
        expect(ordered.last.config['multiplier_value'], 2);
      },
    );

    test('matchesHash compares against the sealed integrity hash', () {
      final s = ForensicEvidenceSnapshot.fromJson(
        _row(integrityHash: _hex('b')),
      );
      expect(s.matchesHash(_hex('b')), isTrue);
      expect(s.matchesHash(_hex('c')), isFalse);
    });

    test('fromJson rejects empty organization_id (INV-1)', () {
      expect(
        () => ForensicEvidenceSnapshot.fromJson(_row(organizationId: '')),
        throwsA(isA<DomainException>()),
      );
    });

    test('fromJson rejects missing integrity_hash (INV-9)', () {
      final row = _row()..remove('integrity_hash');
      expect(
        () => ForensicEvidenceSnapshot.fromJson(row),
        throwsA(isA<DomainException>()),
      );
    });
  });
}
