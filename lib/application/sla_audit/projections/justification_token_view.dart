import 'package:veraprob/domain/sla_audit/justification/justification_submission_token.dart';

/// Read model for [JustificationSubmissionToken] used in presentation layer.
class JustificationTokenView {
  final String id;
  final String organizationId;
  final String contractId;
  final String setId;
  final String token;
  final String createdByUserId;
  final DateTime expiresAtUtc;
  final DateTime? usedAtUtc;
  final DateTime createdAtUtc;
  final String? justificationId;

  const JustificationTokenView({
    required this.id,
    required this.organizationId,
    required this.contractId,
    required this.setId,
    required this.token,
    required this.createdByUserId,
    required this.expiresAtUtc,
    this.usedAtUtc,
    required this.createdAtUtc,
    this.justificationId,
  });

  bool get isConsumed => usedAtUtc != null;

  factory JustificationTokenView.fromDomain(
    JustificationSubmissionToken domain,
  ) {
    return JustificationTokenView(
      id: domain.id,
      organizationId: domain.organizationId,
      contractId: domain.contractId,
      setId: domain.setId,
      token: domain.token,
      createdByUserId: domain.createdByUserId,
      expiresAtUtc: domain.expiresAtUtc,
      usedAtUtc: domain.usedAtUtc,
      createdAtUtc: domain.createdAtUtc,
      justificationId: domain.justificationId,
    );
  }
}
