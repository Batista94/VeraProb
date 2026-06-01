import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_forensic_evidence_snapshot_repository.dart';

void main() {
  late InMemoryForensicEvidenceSnapshotRepository repo;

  final occurred = DateTime.utc(2026, 8, 1, 12);

  setUp(() {
    repo = InMemoryForensicEvidenceSnapshotRepository();
    repo.seedRules(
      organizationId: 'org-A',
      contractId: 'contract-1',
      ruleSetId: 'rs-1',
      slaRuleVersion: 2,
      rules: [
        {
          'rule_id': 'rule-1',
          'rule_type': 'NO_SHOW_PENALTY',
          'rule_config': {'multiplier_value': 2},
          'rule_version': 2,
          'evaluation_order': 0,
        },
      ],
    );
  });

  Future<ForensicEvidenceSnapshot> seal({String idempotencyKey = 'idem-1'}) =>
      repo.seal(
        organizationId: 'org-A',
        contractId: 'contract-1',
        setId: 'set-1',
        verdictType: 'NO_SHOW_PENALTY',
        planVersion: 1,
        occurredAtUtc: occurred,
        sealedBy: 'user-1',
        idempotencyKey: idempotencyKey,
      );

  test('seal freezes the active rule and computes an integrity hash', () async {
    final s = await seal();
    expect(s.organizationId, 'org-A');
    expect(s.slaRuleVersion, 2);
    expect(s.integrityHash, hasLength(64));
    expect(s.rules.orderedRules.single.config['multiplier_value'], 2);
    expect(repo.count, 1);
  });

  test('seal is idempotent on (org, idempotencyKey)', () async {
    final first = await seal();
    final second = await seal();
    expect(second.id, first.id);
    expect(repo.count, 1);
  });

  test('seal rejects a contract with no active rule (Req 5.3)', () async {
    expect(
      () => repo.seal(
        organizationId: 'org-A',
        contractId: 'unknown',
        setId: 'set-1',
        verdictType: 'NO_SHOW_PENALTY',
        planVersion: 1,
        occurredAtUtc: occurred,
        sealedBy: 'user-1',
        idempotencyKey: 'idem-x',
      ),
      throwsA(isA<IntegrityException>()),
    );
  });

  test('findByLedgerEntry isolates tenants (INV-22 / 404 parity)', () async {
    final s = await seal();
    final sameOrg = await repo.findByLedgerEntry(
      organizationId: 'org-A',
      ledgerEntryId: s.ledgerEntryId,
    );
    final otherOrg = await repo.findByLedgerEntry(
      organizationId: 'org-B',
      ledgerEntryId: s.ledgerEntryId,
    );
    expect(sameOrg, isNotNull);
    expect(otherOrg, isNull);
  });

  test('verify returns authentic for an untouched snapshot (Req 8)', () async {
    final s = await seal();
    final result = await repo.verify(
      organizationId: 'org-A',
      ledgerEntryId: s.ledgerEntryId,
    );
    expect(result.isAuthentic, isTrue);
    expect(result.storedHash, result.computedHash);
  });

  test('verify detects tampering (Req 2.5 / 8.5)', () async {
    final s = await seal();
    repo.tamper(s.ledgerEntryId);
    expect(
      () =>
          repo.verify(organizationId: 'org-A', ledgerEntryId: s.ledgerEntryId),
      throwsA(isA<IntegrityException>()),
    );
  });

  test('verify on unknown verdict throws ResourceNotFound (INV-26)', () async {
    expect(
      () => repo.verify(organizationId: 'org-A', ledgerEntryId: 'missing'),
      throwsA(isA<ResourceNotFoundException>()),
    );
  });
}
