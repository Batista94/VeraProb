import 'contractor_justification.dart';
import 'justification_evidence.dart';
import 'justification_status.dart';
import 'justification_submission_token.dart';

/// Abstract repository interface for all justification operations.
///
/// Implementations: [InMemoryJustificationRepository] (tests),
/// [PostgresJustificationRepository] (production).
abstract class JustificationRepository {
  // ── Justification CRUD ────────────────────────────────────────────────────

  /// Persists a new justification. Returns the created entity.
  Future<ContractorJustification> create(ContractorJustification justification);

  /// Loads a single justification by [id], scoped to [organizationId] (INV-1).
  /// Returns null when not found or outside tenant scope.
  Future<ContractorJustification?> findById({
    required String id,
    required String organizationId,
  });

  /// Returns all justifications for [organizationId], newest first.
  /// Optional [contractId] filter narrows to a single contract.
  Future<List<ContractorJustification>> listByOrg({
    required String organizationId,
    String? contractId,
    JustificationStatus? status,
    int limit = 100,
  });

  /// Updates only the review fields (status, reviewer, timestamp).
  /// The DB immutability trigger enforces that no other fields change.
  Future<ContractorJustification> updateStatus({
    required String id,
    required String organizationId,
    required JustificationStatus status,
    required String reviewedByUserId,
    required DateTime reviewedAtUtc,
  });

  // ── Evidence ──────────────────────────────────────────────────────────────

  /// Appends an evidence record to an existing justification (INV-7/INV-8).
  Future<JustificationEvidence> addEvidence(JustificationEvidence evidence);

  /// Returns all evidence for [justificationId], scoped to [organizationId].
  Future<List<JustificationEvidence>> getEvidence({
    required String justificationId,
    required String organizationId,
  });

  // ── Submission tokens ─────────────────────────────────────────────────────

  /// Persists a new submission token.
  Future<JustificationSubmissionToken> createToken(
    JustificationSubmissionToken token,
  );

  /// Loads a token by its public [tokenValue] (the UUID in the URL).
  /// Returns null when not found.
  Future<JustificationSubmissionToken?> findToken(String tokenValue);

  /// Calls the `use_justification_token` RPC atomically.
  /// Returns the ID of the newly created justification.
  Future<String> useToken({
    required String tokenValue,
    required String category,
    required String description,
  });
}
