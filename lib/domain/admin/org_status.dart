import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Organization lifecycle status.
///
/// Lifecycle: TRIAL → ACTIVE → SUSPENDED → CHURNED → ARCHIVED → DELETED
/// ARCHIVED = data preserved read-only. DELETED = GDPR hard-remove.
///
/// INV-10: Invalid status strings throw [IntegrityException].
enum OrgStatus {
  trial,
  active,
  suspended,
  churned,
  archived,
  deleted;

  /// Whether the organization can operate (receive telemetry, run evaluations).
  bool get isOperational => this == active || this == trial;

  /// Whether the organization is visible in normal tenant lists.
  bool get isVisible => this != deleted;

  /// Database value (uppercase to match CHECK constraint).
  String get dbValue => name.toUpperCase();

  /// Parse from database string. Throws [IntegrityException] on invalid value.
  static OrgStatus fromString(String value) {
    return IntegrityException.shield(values, value.toLowerCase(), 'status');
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case OrgStatus.trial:
        return 'Trial';
      case OrgStatus.active:
        return 'Ativo';
      case OrgStatus.suspended:
        return 'Suspenso';
      case OrgStatus.churned:
        return 'Churned';
      case OrgStatus.archived:
        return 'Arquivado';
      case OrgStatus.deleted:
        return 'Excluído';
    }
  }
}
