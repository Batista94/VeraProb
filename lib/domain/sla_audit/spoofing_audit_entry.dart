import 'dart:convert' show utf8, jsonEncode;
import 'package:crypto/crypto.dart' show sha256;
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/core/utils/date_time_provider.dart';
import 'spoofing_risk_score.dart';

/// Append-only audit entry documenting an algorithmic detection of
/// potential GPS spoofing for a specific device window.
///
/// Implements INV-21 / Phase 8.8 requirement for tamper-evident audit trails.
class SpoofingAuditEntry extends Equatable {
  final String id;
  final String organizationId;
  final String deviceId;
  final String? assetId;

  /// Start and end of the temporal window analyzed.
  final DateTime windowStart;
  final DateTime windowEnd;

  /// Algorithmic result (heuristics used, raw score).
  final SpoofingRiskScore riskScore;

  /// Number of facts in the analyzed window.
  final int factsAnalyzed;

  /// IDs of the specific [CanonicalFact] records that form the evidence pool.
  final List<String> factIds;

  /// Tamper-evident hash of the entry content (INV-16 / INV-21).
  /// Required by [QALead] for legally-defensible forensic evidence.
  final String contentHash;

  /// UTC timestamp of server-side creation.
  final DateTime createdAt;

  // -- Review Status (Nullable) --

  /// Auditor user ID who reviewed this entry.
  final String? reviewedBy;
  final DateTime? reviewedAt;

  /// Audit outcome: 'cleared' (false positive) or 'confirmed' (authorized audit).
  final String? reviewOutcome;

  const SpoofingAuditEntry._({
    required this.id,
    required this.organizationId,
    required this.deviceId,
    this.assetId,
    required this.windowStart,
    required this.windowEnd,
    required this.riskScore,
    required this.factsAnalyzed,
    required this.factIds,
    required this.contentHash,
    required this.createdAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewOutcome,
  });

  /// Factory for creating a new append-only entry after detection.
  /// Automatically computes the SHA-256 [contentHash].
  factory SpoofingAuditEntry.create({
    required String organizationId,
    required String deviceId,
    String? assetId,
    required DateTime windowStart,
    required DateTime windowEnd,
    required SpoofingRiskScore riskScore,
    required int factsAnalyzed,
    required List<String> factIds,
  }) {
    final now =
        StaticDateTimeProvider.instance?.nowUtc() ?? DateTime.now().toUtc();
    final id = const Uuid().v4();

    // Deterministic payload for hashing
    final payload = {
      'id': id,
      'org': organizationId,
      'dev': deviceId,
      'winStart': windowStart.toIso8601String(),
      'winEnd': windowEnd.toIso8601String(),
      'score': riskScore.scoreBps,
      'signalCount': riskScore.signals.length,
      'factCount': factsAnalyzed,
      'factIds': factIds..sort(), // Order-independent hash
    };

    final hash = sha256.convert(utf8.encode(jsonEncode(payload))).toString();

    return SpoofingAuditEntry._(
      id: id,
      organizationId: organizationId,
      deviceId: deviceId,
      assetId: assetId,
      windowStart: windowStart,
      windowEnd: windowEnd,
      riskScore: riskScore,
      factsAnalyzed: factsAnalyzed,
      factIds: factIds,
      contentHash: hash,
      createdAt: now,
    );
  }

  /// Reconstitutes from storage.
  factory SpoofingAuditEntry.reconstitute({
    required String id,
    required String organizationId,
    required String deviceId,
    String? assetId,
    required DateTime windowStart,
    required DateTime windowEnd,
    required SpoofingRiskScore riskScore,
    required int factsAnalyzed,
    required List<String> factIds,
    required String contentHash,
    required DateTime createdAt,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? reviewOutcome,
  }) {
    return SpoofingAuditEntry._(
      id: id,
      organizationId: organizationId,
      deviceId: deviceId,
      assetId: assetId,
      windowStart: windowStart,
      windowEnd: windowEnd,
      riskScore: riskScore,
      factsAnalyzed: factsAnalyzed,
      factIds: factIds,
      contentHash: contentHash,
      createdAt: createdAt,
      reviewedBy: reviewedBy,
      reviewedAt: reviewedAt,
      reviewOutcome: reviewOutcome,
    );
  }

  @override
  List<Object?> get props => [id, contentHash];
}
