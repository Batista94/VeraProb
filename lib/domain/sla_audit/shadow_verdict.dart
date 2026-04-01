import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'domain_exception.dart';
import 'verdict_evidence.dart';

/// Divergence classification between the shadow engine and a human auditor.
enum ShadowDivergenceType {
  /// Engine verdict matches the human decision.
  match,

  /// Engine recommended penalty; human rejected it.
  falsePositive,

  /// Engine found no violation; human applied a penalty.
  falseNegative,

  /// No human decision recorded yet — comparison deferred.
  pendingManual,
}

/// Entity: one shadow execution of the [ContractualEvaluationEngine]
/// against a real obligation.
///
/// Shadow verdicts are **immutable once created** — engine-produced fields
/// (verdict, evidence, hash, version, timestamp) cannot change after
/// [fromEngineResult] constructs the entity. Only [withManualVerdict] produces
/// an updated copy, and only for the manual-classification fields.
///
/// **Invariants enforced:**
/// - INV-1:  [organizationId] is mandatory on every row.
/// - INV-7:  DB trigger prevents UPDATE of engine fields; mirrors entity
///           immutability at the persistence layer.
/// - INV-9:  [engineVerdictAtUtc] and [createdAtUtc] are UTC.
/// - INV-18: Pure Dart — zero Flutter/Supabase dependencies.
/// - INV-22: [traceabilityHash] = SHA-256 of a canonical JSON payload,
///           deterministically linking this verdict to its causal facts.
class ShadowVerdict extends Equatable {
  final String id;
  final String organizationId;
  final String setId;
  final String contractId;

  /// One of: 'executed' | 'noShow' | 'evidenceGap' | 'inhibited'
  final String engineVerdict;

  /// UTC timestamp of when the engine produced this verdict (INV-9).
  final DateTime engineVerdictAtUtc;

  /// WASM build version that produced this verdict.
  /// Resolved from [EnvironmentConfig.engineVersion] at call-site —
  /// never hardcoded here (dynamic versioning refinement).
  final String engineVersion;

  /// Full forensic evidence bundle that justified the verdict (INV-22).
  final VerdictEvidence verdictEvidence;

  /// SHA-256 of the canonical JSON payload linking verdict to causal facts.
  /// Deterministic: same inputs → same hash (INV-22).
  final String traceabilityHash;

  /// Divergence classification against the human reviewer's decision.
  final ShadowDivergenceType divergenceType;

  /// Human decision: 'applied' or 'rejected'. Null until [syncManualVerdicts].
  final String? manualVerdict;

  /// UTC timestamp of the human decision (INV-9).
  final DateTime? manualVerdictAtUtc;

  /// UUID of the auditor who reviewed the sanction queue entry.
  final String? manualReviewedBy;

  /// UTC timestamp of row creation (INV-9).
  final DateTime createdAtUtc;

  const ShadowVerdict._({
    required this.id,
    required this.organizationId,
    required this.setId,
    required this.contractId,
    required this.engineVerdict,
    required this.engineVerdictAtUtc,
    required this.engineVersion,
    required this.verdictEvidence,
    required this.traceabilityHash,
    required this.divergenceType,
    required this.createdAtUtc,
    this.manualVerdict,
    this.manualVerdictAtUtc,
    this.manualReviewedBy,
  });

  /// Constructs a new [ShadowVerdict] from an engine evaluation result.
  ///
  /// Computes [traceabilityHash] deterministically from the canonical payload.
  /// Caller must supply [engineVersion] from [EnvironmentConfig.engineVersion].
  ///
  /// Throws [DomainException] on invariant violations.
  factory ShadowVerdict.fromEngineResult({
    required String organizationId,
    required String setId,
    required String contractId,
    required String engineVerdict,
    required DateTime engineVerdictAtUtc,
    required String engineVersion,
    required VerdictEvidence verdictEvidence,
    DateTime? createdAtUtc,
  }) {
    if (organizationId.trim().isEmpty) {
      throw const DomainException('organizationId must not be empty (INV-1)');
    }
    if (setId.trim().isEmpty) {
      throw const DomainException('setId must not be empty');
    }
    if (contractId.trim().isEmpty) {
      throw const DomainException('contractId must not be empty');
    }
    const validVerdicts = {'executed', 'noShow', 'evidenceGap', 'inhibited'};
    if (!validVerdicts.contains(engineVerdict)) {
      throw DomainException(
        'engineVerdict must be one of $validVerdicts, got: $engineVerdict',
      );
    }
    if (!engineVerdictAtUtc.isUtc) {
      throw const DomainException(
        'engineVerdictAtUtc must be UTC (INV-9). Call .toUtc() before passing.',
      );
    }
    if (engineVersion.trim().isEmpty) {
      throw const DomainException(
        'engineVersion must not be empty. Pass EnvironmentConfig.engineVersion.',
      );
    }

    final effectiveCreatedAt = createdAtUtc ?? DateTime.now().toUtc();
    if (!effectiveCreatedAt.isUtc) {
      throw const DomainException('createdAtUtc must be UTC (INV-9)');
    }

    final hash = _computeTraceabilityHash(
      engineVerdict: engineVerdict,
      evidenceHash: verdictEvidence.evidenceHash,
      setId: setId,
      contractId: contractId,
      engineVerdictAtUtc: engineVerdictAtUtc,
      engineVersion: engineVersion,
    );

    return ShadowVerdict._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      setId: setId,
      contractId: contractId,
      engineVerdict: engineVerdict,
      engineVerdictAtUtc: engineVerdictAtUtc,
      engineVersion: engineVersion,
      verdictEvidence: verdictEvidence,
      traceabilityHash: hash,
      divergenceType: ShadowDivergenceType.pendingManual,
      createdAtUtc: effectiveCreatedAt,
    );
  }

  /// Reconstitutes from persistence. Does NOT recompute hash — trusts stored value.
  factory ShadowVerdict.fromJson(Map<String, dynamic> json) {
    return ShadowVerdict._(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      setId: json['set_id'] as String,
      contractId: json['contract_id'] as String,
      engineVerdict: json['engine_verdict'] as String,
      engineVerdictAtUtc: DateTime.parse(
        json['engine_verdict_at_utc'] as String,
      ),
      engineVersion: json['engine_version'] as String,
      verdictEvidence: VerdictEvidence.fromJson(
        json['verdict_evidence'] as Map<String, dynamic>,
      ),
      traceabilityHash: json['traceability_hash'] as String,
      divergenceType: _divergenceFromString(
        json['divergence_type'] as String,
      ),
      manualVerdict: json['manual_verdict'] as String?,
      manualVerdictAtUtc: json['manual_verdict_at_utc'] != null
          ? DateTime.parse(json['manual_verdict_at_utc'] as String)
          : null,
      manualReviewedBy: json['manual_reviewed_by'] as String?,
      createdAtUtc: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'set_id': setId,
        'contract_id': contractId,
        'engine_verdict': engineVerdict,
        'engine_verdict_at_utc': engineVerdictAtUtc.toIso8601String(),
        'engine_version': engineVersion,
        'verdict_evidence': verdictEvidence.toJson(),
        'traceability_hash': traceabilityHash,
        'divergence_type': _divergenceToString(divergenceType),
        'manual_verdict': manualVerdict,
        'manual_verdict_at_utc': manualVerdictAtUtc?.toIso8601String(),
        'manual_reviewed_by': manualReviewedBy,
        'created_at': createdAtUtc.toIso8601String(),
      };

  /// Returns an updated copy with the human auditor's decision applied.
  ///
  /// Engine-produced fields are preserved unchanged — this is a projection
  /// of the manual review outcome onto the existing shadow verdict.
  ShadowVerdict withManualVerdict({
    required String manualVerdict,
    required DateTime manualVerdictAtUtc,
    required String manualReviewedBy,
  }) {
    if (!manualVerdictAtUtc.isUtc) {
      throw const DomainException('manualVerdictAtUtc must be UTC (INV-9)');
    }
    return ShadowVerdict._(
      id: id,
      organizationId: organizationId,
      setId: setId,
      contractId: contractId,
      engineVerdict: engineVerdict,
      engineVerdictAtUtc: engineVerdictAtUtc,
      engineVersion: engineVersion,
      verdictEvidence: verdictEvidence,
      traceabilityHash: traceabilityHash,
      divergenceType: _classifyDivergence(
        engineVerdict: engineVerdict,
        manualVerdict: manualVerdict,
      ),
      manualVerdict: manualVerdict,
      manualVerdictAtUtc: manualVerdictAtUtc,
      manualReviewedBy: manualReviewedBy,
      createdAtUtc: createdAtUtc,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Canonical payload for traceability hashing.
  /// Field order is fixed — do not reorder (INV-22).
  static String _computeTraceabilityHash({
    required String engineVerdict,
    required String evidenceHash,
    required String setId,
    required String contractId,
    required DateTime engineVerdictAtUtc,
    required String engineVersion,
  }) {
    final canonical = <String, dynamic>{
      'shadow_verdict': engineVerdict,
      'evidence_hash': evidenceHash,
      'set_id': setId,
      'contract_id': contractId,
      'engine_verdict_at_utc': engineVerdictAtUtc.toIso8601String(),
      'engine_version': engineVersion,
    };
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  /// Divergence table:
  /// - executed/noShow + applied  → match
  /// - executed/noShow + rejected → false_positive
  /// - evidenceGap    + rejected  → match
  /// - evidenceGap    + applied   → false_negative
  /// - inhibited      + rejected  → match
  /// - inhibited      + applied   → false_negative  ← engine too lenient
  /// - any            + null      → pending_manual
  ///
  /// Rationale for inhibited+applied → false_negative:
  /// Shadow Mode must surface cases where the engine suppressed a penalty
  /// (via MAINTENANCE or State Inhibition — INV-15) but a human auditor
  /// still applied one. Classifying these as 'match' would hide potential
  /// logic failures in the inhibition path of the EvaluationEngine.
  static ShadowDivergenceType _classifyDivergence({
    required String engineVerdict,
    required String manualVerdict,
  }) {
    switch (engineVerdict) {
      case 'executed':
      case 'noShow':
        return manualVerdict == 'applied'
            ? ShadowDivergenceType.match
            : ShadowDivergenceType.falsePositive;
      case 'evidenceGap':
        return manualVerdict == 'rejected'
            ? ShadowDivergenceType.match
            : ShadowDivergenceType.falseNegative;
      case 'inhibited':
        return manualVerdict == 'applied'
            ? ShadowDivergenceType.falseNegative
            : ShadowDivergenceType.match;
      default:
        return ShadowDivergenceType.pendingManual;
    }
  }

  static ShadowDivergenceType _divergenceFromString(String value) =>
      switch (value) {
        'match' => ShadowDivergenceType.match,
        'false_positive' => ShadowDivergenceType.falsePositive,
        'false_negative' => ShadowDivergenceType.falseNegative,
        _ => ShadowDivergenceType.pendingManual,
      };

  static String _divergenceToString(ShadowDivergenceType type) =>
      switch (type) {
        ShadowDivergenceType.match => 'match',
        ShadowDivergenceType.falsePositive => 'false_positive',
        ShadowDivergenceType.falseNegative => 'false_negative',
        ShadowDivergenceType.pendingManual => 'pending_manual',
      };

  @override
  List<Object?> get props => [id];
}
