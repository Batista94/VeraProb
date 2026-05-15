import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// The discrete phase of the SLA justification submission pipeline where a
/// forensic invariant was violated.
///
/// Tagging exceptions with a [JustificationPhase] gives the audit trail and the
/// user-facing error interpreter granular, Tier-1 traceability without parsing
/// free-text messages.
enum JustificationPhase {
  /// INV-1 tenant identity sync.
  identity,

  /// Category / description sanitization and validation.
  input,

  /// CX05-INV-23 evidence sealing — hash format and binary signature checks.
  evidence,

  /// CX05-INV-22 expiration window.
  temporal,

  /// CX05-INV-20 event linkage and anti-double-dipping.
  linkage,

  /// Atomic persistence and server-side hash re-verification.
  persistence,
}

/// Domain-layer exception for SLA justification invariant violations.
///
/// Extends [DomainException] so existing `isA<DomainException>()` handlers and
/// assertions keep working, while [phase] adds the granular forensic context
/// required for the client defense dossier.
class JustificationException extends DomainException {
  final JustificationPhase phase;

  const JustificationException(super.message, {required this.phase});

  @override
  String toString() => 'JustificationException[${phase.name}]: $message';
}
