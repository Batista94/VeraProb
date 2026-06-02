import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/infrastructure/shared/canonical_json.dart';

/// In-memory implementation of [ForensicEvidenceSnapshotRepository] for unit
/// testing. Mirrors the `seal_forensic_evidence` RPC behaviour:
/// - resolves the active rule from seeded data ([seedRules]) — Backend Authority;
/// - appends a synthetic ledger entry and binds the snapshot to it;
/// - computes a deterministic SHA-256 hash over the canonical snapshot (INV-9/15);
/// - is idempotent on (organizationId, idempotencyKey) — replay returns existing.
class InMemoryForensicEvidenceSnapshotRepository
    implements ForensicEvidenceSnapshotRepository {
  final List<Map<String, dynamic>> _rows = [];
  final Map<String, _SeededRuleSet> _seeded = {};
  int _counter = 0;

  /// Seeds the active rule set the seal RPC would resolve for [contractId].
  /// [rules] are snake_case rule items (rule_id, rule_type, rule_config,
  /// rule_version, evaluation_order).
  void seedRules({
    required String organizationId,
    required String contractId,
    required String ruleSetId,
    required List<Map<String, dynamic>> rules,
    required int slaRuleVersion,
    DateTime? effectiveFromUtc,
    DateTime? effectiveToUtc,
  }) {
    _seeded['$organizationId::$contractId'] = _SeededRuleSet(
      ruleSetId: ruleSetId,
      rules: rules,
      slaRuleVersion: slaRuleVersion,
      effectiveFromUtc: effectiveFromUtc,
      effectiveToUtc: effectiveToUtc,
    );
  }

  @override
  Future<ForensicEvidenceSnapshot> seal({
    required String organizationId,
    required String contractId,
    required String setId,
    required String verdictType,
    required int planVersion,
    required DateTime occurredAtUtc,
    required String sealedBy,
    required String idempotencyKey,
  }) async {
    final existing = _rows.firstWhere(
      (r) =>
          r['organization_id'] == organizationId &&
          r['idempotency_key'] == idempotencyKey,
      orElse: () => const {},
    );
    if (existing.isNotEmpty) return ForensicEvidenceSnapshot.fromJson(existing);

    final seeded = _seeded['$organizationId::$contractId'];
    if (seeded == null) {
      throw IntegrityException(
        'No active SLA rule for contract $contractId (Req 5.3)',
        field: 'contract_id',
      );
    }

    final ledgerEntryId = 'ledger-${_counter++}';
    final snapshot = <String, dynamic>{
      'schema_version': 1,
      'organization_id': organizationId,
      'contract_id': contractId,
      'rule_set_id': seeded.ruleSetId,
      'sla_rule_version': seeded.slaRuleVersion,
      'effective_from_utc': seeded.effectiveFromUtc?.toUtc().toIso8601String(),
      'effective_to_utc': seeded.effectiveToUtc?.toUtc().toIso8601String(),
      'verdict_type': verdictType,
      'set_id': setId,
      'plan_version': planVersion,
      'occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
      'ledger_entry_id': ledgerEntryId,
      'rules': seeded.rules,
    };

    final row = <String, dynamic>{
      'id': 'fes-${_counter++}',
      'organization_id': organizationId,
      'ledger_entry_id': ledgerEntryId,
      'contract_id': contractId,
      'rule_set_id': seeded.ruleSetId,
      'sla_rule_version': seeded.slaRuleVersion,
      'schema_version': 1,
      'effective_from_utc': seeded.effectiveFromUtc?.toUtc().toIso8601String(),
      'effective_to_utc': seeded.effectiveToUtc?.toUtc().toIso8601String(),
      'snapshot': snapshot,
      'integrity_hash': _hash(snapshot),
      'idempotency_key': idempotencyKey,
      'sealed_by': sealedBy,
      'sealed_at_utc': occurredAtUtc.toUtc().toIso8601String(),
    };
    _rows.add(row);
    return ForensicEvidenceSnapshot.fromJson(row);
  }

  @override
  Future<ForensicEvidenceSnapshot?> findByLedgerEntry({
    required String organizationId,
    required String ledgerEntryId,
  }) async {
    final row = _rows.firstWhere(
      (r) =>
          r['organization_id'] == organizationId &&
          r['ledger_entry_id'] == ledgerEntryId,
      orElse: () => const {},
    );
    if (row.isEmpty) return null;
    return ForensicEvidenceSnapshot.fromJson(row);
  }

  @override
  Future<List<ForensicEvidenceSnapshot>> findByOrganization({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 100,
  }) async {
    final out =
        _rows
            .where((r) => r['organization_id'] == organizationId)
            .map(ForensicEvidenceSnapshot.fromJson)
            .where(
              (s) =>
                  !s.sealedAtUtc.isBefore(fromUtc) &&
                  !s.sealedAtUtc.isAfter(toUtc),
            )
            .toList()
          ..sort((a, b) => b.sealedAtUtc.compareTo(a.sealedAtUtc));
    return out.take(limit).toList();
  }

  @override
  Future<EvidenceVerification> verify({
    required String organizationId,
    required String ledgerEntryId,
  }) async {
    final row = _rows.firstWhere(
      (r) =>
          r['organization_id'] == organizationId &&
          r['ledger_entry_id'] == ledgerEntryId,
      orElse: () => const {},
    );
    if (row.isEmpty) {
      throw ResourceNotFoundException(
        resourceType: 'forensic_evidence_snapshot',
        resourceId: ledgerEntryId,
      );
    }

    final stored = row['integrity_hash'] as String;
    final computed = _hash(row['snapshot'] as Map<String, dynamic>);
    if (stored != computed) {
      throw IntegrityException(
        'Forensic snapshot integrity check failed for verdict $ledgerEntryId. '
        'Potential tampering.',
        field: 'integrity_hash',
      );
    }
    return EvidenceVerification(
      ledgerEntryId: ledgerEntryId,
      status: EvidenceVerificationStatus.authentic,
      storedHash: stored,
      computedHash: computed,
      snapshot: ForensicEvidenceSnapshot.fromJson(row),
    );
  }

  // ── Test helpers ───────────────────────────────────────────────────────────

  /// Simulates an insider mutating sealed content without re-sealing the hash.
  void tamper(String ledgerEntryId) {
    final row = _rows.firstWhere((r) => r['ledger_entry_id'] == ledgerEntryId);
    (row['snapshot'] as Map<String, dynamic>)['rules'] = <dynamic>[];
  }

  int get count => _rows.length;
  void clear() {
    _rows.clear();
    _seeded.clear();
    _counter = 0;
  }

  static String _hash(Map<String, dynamic> snapshot) =>
      sha256.convert(utf8.encode(canonicalJsonEncode(snapshot))).toString();
}

class _SeededRuleSet {
  final String ruleSetId;
  final List<Map<String, dynamic>> rules;
  final int slaRuleVersion;
  final DateTime? effectiveFromUtc;
  final DateTime? effectiveToUtc;

  const _SeededRuleSet({
    required this.ruleSetId,
    required this.rules,
    required this.slaRuleVersion,
    required this.effectiveFromUtc,
    required this.effectiveToUtc,
  });
}
