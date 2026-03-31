import 'package:uuid/uuid.dart';

import '../../../domain/sla_audit/justification/contractor_justification.dart';
import '../../../domain/sla_audit/justification/justification_evidence.dart';
import '../../../domain/sla_audit/justification/justification_repository.dart';
import '../../../domain/sla_audit/justification/justification_status.dart';
import '../../../domain/sla_audit/justification/justification_submission_token.dart';

/// In-memory implementation of [JustificationRepository].
///
/// Used in unit tests. All operations are O(n) linear scan.
class InMemoryJustificationRepository implements JustificationRepository {
  final List<ContractorJustification> _justifications = [];
  final List<JustificationEvidence> _evidence = [];
  final List<JustificationSubmissionToken> _tokens = [];

  // ── Justifications ────────────────────────────────────────────────────────

  @override
  Future<ContractorJustification> create(
    ContractorJustification justification,
  ) async {
    _justifications.add(justification);
    return justification;
  }

  @override
  Future<ContractorJustification?> findById({
    required String id,
    required String organizationId,
  }) async {
    try {
      return _justifications.firstWhere(
        (j) => j.id == id && j.organizationId == organizationId,
      );
    } on StateError {
      return null;
    }
  }

  @override
  Future<List<ContractorJustification>> listByOrg({
    required String organizationId,
    String? contractId,
    JustificationStatus? status,
    int limit = 100,
  }) async {
    return _justifications
        .where((j) {
          if (j.organizationId != organizationId) return false;
          if (contractId != null && j.contractId != contractId) return false;
          if (status != null && j.status != status) return false;
          return true;
        })
        .take(limit)
        .toList();
  }

  @override
  Future<ContractorJustification> updateStatus({
    required String id,
    required String organizationId,
    required JustificationStatus status,
    required String reviewedByUserId,
    required DateTime reviewedAtUtc,
  }) async {
    final index = _justifications.indexWhere(
      (j) => j.id == id && j.organizationId == organizationId,
    );
    if (index == -1) {
      throw StateError('Justification $id not found for org $organizationId.');
    }
    final updated = _justifications[index].copyWith(
      status: status,
      reviewedByUserId: reviewedByUserId,
      reviewedAtUtc: reviewedAtUtc,
    );
    _justifications[index] = updated;
    return updated;
  }

  // ── Evidence ──────────────────────────────────────────────────────────────

  @override
  Future<JustificationEvidence> addEvidence(
    JustificationEvidence evidence,
  ) async {
    _evidence.add(evidence);
    return evidence;
  }

  @override
  Future<List<JustificationEvidence>> getEvidence({
    required String justificationId,
    required String organizationId,
  }) async {
    return _evidence
        .where(
          (e) =>
              e.justificationId == justificationId &&
              e.organizationId == organizationId,
        )
        .toList();
  }

  // ── Submission tokens ─────────────────────────────────────────────────────

  @override
  Future<JustificationSubmissionToken> createToken(
    JustificationSubmissionToken token,
  ) async {
    _tokens.add(token);
    return token;
  }

  @override
  Future<JustificationSubmissionToken?> findToken(String tokenValue) async {
    try {
      return _tokens.firstWhere((t) => t.token == tokenValue);
    } on StateError {
      return null;
    }
  }

  @override
  Future<String> useToken({
    required String tokenValue,
    required String category,
    required String description,
  }) async {
    // In-memory stub: simply returns a new UUID.
    // Real implementation calls the `use_justification_token` RPC.
    return const Uuid().v4();
  }
}
