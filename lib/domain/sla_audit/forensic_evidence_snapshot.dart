import 'package:equatable/equatable.dart';

import 'contractual_rule.dart';
import 'domain_exception.dart';
import 'rule_snapshot.dart';

/// Aggregate root: an immutable, cryptographically sealed snapshot of the SLA
/// rule that was active at the moment a verdict was sealed.
///
/// Created exclusively by the `seal_forensic_evidence` Backend-Authority RPC and
/// reconstituted here from its result. The vault is append-only — there is no
/// mutating operation on this entity.
///
/// **Invariants enforced:**
/// - INV-1:  [organizationId] is mandatory.
/// - INV-3:  No mutation — DB triggers reject UPDATE/DELETE; entity is immutable.
/// - INV-6:  [sealedAtUtc] / effective range are UTC.
/// - INV-9:  [integrityHash] is the DB-computed SHA-256 of the canonical
///           [snapshot]. The database is the sole hashing authority — this entity
///           never recomputes it (avoids canonical-format drift).
/// - INV-18: Pure Dart — zero Flutter/Supabase dependencies.
/// - INV-21: [ledgerEntryId] binds the verdict to this snapshot.
class ForensicEvidenceSnapshot extends Equatable {
  final String id;
  final String organizationId;

  /// The sealed verdict (sla_audit_ledger_v2 entry) this snapshot proves.
  final String ledgerEntryId;
  final String contractId;
  final String ruleSetId;
  final int slaRuleVersion;
  final int schemaVersion;

  final DateTime? effectiveFromUtc;
  final DateTime? effectiveToUtc;

  /// The frozen, canonical rule content exactly as hashed by the database.
  /// Kept verbatim (the hashing authority is the DB) — see [rules] for the
  /// typed projection of the embedded rule list.
  final Map<String, dynamic> snapshot;

  /// SHA-256 hex of the canonical [snapshot], computed by the database.
  final String integrityHash;

  /// UUID of the operator who sealed the verdict.
  final String sealedBy;

  /// UTC timestamp of sealing (server-clock authority).
  final DateTime sealedAtUtc;

  const ForensicEvidenceSnapshot._({
    required this.id,
    required this.organizationId,
    required this.ledgerEntryId,
    required this.contractId,
    required this.ruleSetId,
    required this.slaRuleVersion,
    required this.schemaVersion,
    required this.effectiveFromUtc,
    required this.effectiveToUtc,
    required this.snapshot,
    required this.integrityHash,
    required this.sealedBy,
    required this.sealedAtUtc,
  });

  /// Reconstitutes from the `seal_forensic_evidence` / vault row JSON.
  ///
  /// Throws [DomainException] on missing mandatory fields or non-UTC timestamps.
  factory ForensicEvidenceSnapshot.fromJson(Map<String, dynamic> json) {
    final organizationId = json['organization_id'] as String?;
    if (organizationId == null || organizationId.trim().isEmpty) {
      throw const DomainException('organization_id missing or empty (INV-1)');
    }
    final integrityHash = json['integrity_hash'] as String?;
    if (integrityHash == null || integrityHash.trim().isEmpty) {
      throw const DomainException('integrity_hash missing (INV-9)');
    }

    final snapshotRaw = json['snapshot'];
    if (snapshotRaw is! Map) {
      throw const DomainException('snapshot content missing or malformed');
    }

    return ForensicEvidenceSnapshot._(
      id: json['id'] as String,
      organizationId: organizationId,
      ledgerEntryId: json['ledger_entry_id'] as String,
      contractId: json['contract_id'] as String,
      ruleSetId: json['rule_set_id'] as String,
      slaRuleVersion: json['sla_rule_version'] as int,
      schemaVersion: json['schema_version'] as int,
      effectiveFromUtc: _parseUtcOrNull(json['effective_from_utc']),
      effectiveToUtc: _parseUtcOrNull(json['effective_to_utc']),
      snapshot: Map<String, dynamic>.from(snapshotRaw),
      integrityHash: integrityHash,
      sealedBy: json['sealed_by'] as String,
      sealedAtUtc: _parseUtc(json['sealed_at_utc'], 'sealed_at_utc'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'organization_id': organizationId,
    'ledger_entry_id': ledgerEntryId,
    'contract_id': contractId,
    'rule_set_id': ruleSetId,
    'sla_rule_version': slaRuleVersion,
    'schema_version': schemaVersion,
    'effective_from_utc': effectiveFromUtc?.toIso8601String(),
    'effective_to_utc': effectiveToUtc?.toIso8601String(),
    'snapshot': snapshot,
    'integrity_hash': integrityHash,
    'sealed_by': sealedBy,
    'sealed_at_utc': sealedAtUtc.toIso8601String(),
  };

  /// Typed projection of the frozen rule list embedded in [snapshot].
  ///
  /// The DB serializes rule keys in snake_case; this adapter maps them onto the
  /// shared [RuleSnapshotItem] type so the rest of the domain reuses one model.
  RuleSnapshot get rules {
    final raw = snapshot['rules'];
    if (raw is! List) return const RuleSnapshot([]);
    final items = raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return RuleSnapshotItem(
        ruleId: m['rule_id'] as String,
        ruleType: SlaRuleType.fromString(m['rule_type'] as String),
        config: Map<String, dynamic>.from(m['rule_config'] as Map),
        ruleVersion: m['rule_version'] as int,
        evaluationOrder: m['evaluation_order'] as int,
      );
    }).toList();
    return RuleSnapshot(items);
  }

  /// True when [other] equals the sealed [integrityHash]. Comparison only — this
  /// entity does not recompute the hash (the DB verify RPC is the authority).
  bool matchesHash(String other) => other == integrityHash;

  static DateTime _parseUtc(dynamic raw, String field) {
    if (raw is! String) {
      throw DomainException('Timestamp "$field" missing or not a String');
    }
    final normalized = (raw.endsWith('Z') || raw.contains('+'))
        ? raw
        : '${raw}Z';
    return DateTime.parse(normalized).toUtc();
  }

  static DateTime? _parseUtcOrNull(dynamic raw) {
    if (raw == null) return null;
    return _parseUtc(raw, 'effective_range');
  }

  @override
  List<Object?> get props => [id];
}
