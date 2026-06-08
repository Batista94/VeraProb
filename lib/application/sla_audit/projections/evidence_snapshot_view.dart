import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';

/// Application-layer projection consumed by [ForensicEvidenceModal].
/// Shields presentation from domain types (INV-13).
enum EvidenceSnapshotStatus { authentic, tampered }

/// Flattened view of a single frozen rule for display purposes.
class FrozenRuleView {
  final String ruleId;
  final int ruleVersion;

  /// Canonical string key, e.g. 'MAX_TOLERANCE_DELAY'. Avoids leaking [SlaRuleType].
  final String ruleTypeKey;
  final Map<String, dynamic> config;

  const FrozenRuleView({
    required this.ruleId,
    required this.ruleVersion,
    required this.ruleTypeKey,
    required this.config,
  });
}

/// Display DTO for the ForensicEvidenceModal — all fields pre-extracted.
class EvidenceSnapshotView {
  final String ledgerEntryId;
  final EvidenceSnapshotStatus status;
  final DateTime? effectiveFromUtc;
  final DateTime? effectiveToUtc;
  final String sealedBy;
  final DateTime sealedAtUtc;
  final String integrityHash;
  final List<FrozenRuleView> rules;

  const EvidenceSnapshotView({
    required this.ledgerEntryId,
    required this.status,
    required this.effectiveFromUtc,
    required this.effectiveToUtc,
    required this.sealedBy,
    required this.sealedAtUtc,
    required this.integrityHash,
    required this.rules,
  });

  factory EvidenceSnapshotView.fromVerification(EvidenceVerification v) {
    final s = v.snapshot;
    return EvidenceSnapshotView(
      ledgerEntryId: v.ledgerEntryId,
      status: EvidenceSnapshotStatus.authentic,
      effectiveFromUtc: s.effectiveFromUtc,
      effectiveToUtc: s.effectiveToUtc,
      sealedBy: s.sealedBy,
      sealedAtUtc: s.sealedAtUtc,
      integrityHash: s.integrityHash,
      rules: s.rules.rules
          .map(
            (r) => FrozenRuleView(
              ruleId: r.ruleId,
              ruleVersion: r.ruleVersion,
              ruleTypeKey: r.ruleType.value,
              config: r.config,
            ),
          )
          .toList(),
    );
  }

  factory EvidenceSnapshotView.tampered(String ledgerEntryId) {
    return EvidenceSnapshotView(
      ledgerEntryId: ledgerEntryId,
      status: EvidenceSnapshotStatus.tampered,
      effectiveFromUtc: null,
      effectiveToUtc: null,
      sealedBy: '',
      sealedAtUtc: DateTime.utc(0),
      integrityHash: '',
      rules: const [],
    );
  }
}
