import 'package:uuid/uuid.dart';

import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_repository.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_submission_token.dart';
import 'generate_justification_token_command.dart';

/// Application handler for [GenerateJustificationTokenCommand].
///
/// Produces a single-use time-limited [JustificationSubmissionToken] that can
/// be shared with a driver as a self-service URL. The token UUID is generated
/// server-side (128-bit collision space satisfies PO-1; no auth required to
/// consume it because brute-force is infeasible).
///
/// [expiresInHours] must be within [1, 72] (PO-6).
class GenerateJustificationTokenHandler {
  final JustificationRepository _justificationRepo;
  final RbacService _rbac;
  final IDateTimeProvider _dateTimeProvider;

  GenerateJustificationTokenHandler({
    required JustificationRepository justificationRepo,
    required RbacService rbac,
    IDateTimeProvider? dateTimeProvider,
  }) : _justificationRepo = justificationRepo,
       _rbac = rbac,
       _dateTimeProvider = dateTimeProvider ?? BrazilDateTimeProvider();

  Future<JustificationSubmissionToken> handle(
    GenerateJustificationTokenCommand command,
  ) async {
    // 1. RBAC — only admin/operator may generate links
    if (!_rbac.can(command.callerRole, UserPermission.canSubmitJustification)) {
      throw const DomainException('Unauthorized.');
    }

    // 2. Expiry validation (PO-6: configurable 1–72 h)
    if (command.expiresInHours < 1 || command.expiresInHours > 72) {
      throw const DomainException(
        'Token expiry must be between 1 and 72 hours.',
      );
    }

    final now = _dateTimeProvider.now();
    final token = JustificationSubmissionToken(
      id: const Uuid().v4(),
      organizationId: command.organizationId,
      contractId: command.contractId,
      setId: command.setId,
      justificationId: null,
      token: const Uuid().v4(),
      createdByUserId: command.callerUserId,
      expiresAtUtc: now.add(Duration(hours: command.expiresInHours)),
      usedAtUtc: null,
      createdAtUtc: now,
    );

    await _justificationRepo.createToken(token);
    return token;
  }
}
