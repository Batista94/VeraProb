// pr_scanner: INV-1 INV-28
/// Typed domain exceptions for the impersonation session lifecycle.
///
/// INV-4: Pure Dart — zero infrastructure dependencies.
/// INV-28: All typed exceptions carry forensic context for audit trail.
library;

import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// [CIA: Confidentiality] Thrown when a non-SuperAdmin role attempts to
/// invoke the impersonation endpoint. Fail-fast before any I/O.
/// INV-1: Only SuperAdmins carry canImpersonateTenant permission.
class AccessDeniedException extends DomainException {
  final String callerRole;

  const AccessDeniedException({required this.callerRole})
    : super(
        'AccessDeniedException: role "$callerRole" lacks canImpersonateTenant.',
      );
}

/// [CIA: Integrity] Thrown when a SuperAdmin, already inside an active
/// impersonation session, attempts to start a second one without first
/// revoking the current session. Prevents "Inception" nesting.
/// INV-28: The DoubleImpersonation scenario must be forensically auditable.
class InvalidImpersonationStateException extends DomainException {
  final String activeSessionId;
  final String targetOrgId;

  const InvalidImpersonationStateException({
    required this.activeSessionId,
    required this.targetOrgId,
  }) : super(
         'InvalidImpersonationStateException: session "$activeSessionId" is '
         'already active for org "$targetOrgId". Revoke it before starting a new one.',
       );
}

/// [CIA: Availability] Thrown when the cascading revocation rule fires —
/// the base SuperAdmin session expired or was revoked while an impersonation
/// session was still active.
/// INV-28: Cascade revocation events must appear in system_audit_log.
class CascadingRevocationException extends DomainException {
  final String impersonationSessionId;
  final String superAdminUserId;

  const CascadingRevocationException({
    required this.impersonationSessionId,
    required this.superAdminUserId,
  }) : super(
         'CascadingRevocationException: base session for "$superAdminUserId" '
         'expired; impersonation session "$impersonationSessionId" forcibly revoked.',
       );
}

/// [CIA: Availability] Thrown when an operation is attempted on an
/// impersonation token that has elapsed its configured TTL.
/// INV-28: TTL violations must be logged with the expired session ID.
class ImpersonationTokenExpiredException extends DomainException {
  final String sessionId;
  final DateTime expiredAt;

  ImpersonationTokenExpiredException({
    required this.sessionId,
    required this.expiredAt,
  }) : super(
         'ImpersonationTokenExpiredException: session "$sessionId" expired at '
         '${expiredAt.toIso8601String()} (UTC).',
       );
}

/// [CIA: Integrity] Thrown when impersonation is attempted against a
/// UserID/OrgID that is soft-deleted, blocked, or does not exist.
/// Fail-fast before token issuance — no token must be generated for
/// an invalid target.
/// INV-26: 404 parity — response is indistinguishable from "does not exist".
class InvalidImpersonationTargetException extends DomainException {
  final String targetId;
  final String reason;

  const InvalidImpersonationTargetException({
    required this.targetId,
    required this.reason,
  }) : super(
         'InvalidImpersonationTargetException: target "$targetId" is invalid — $reason.',
       );
}
