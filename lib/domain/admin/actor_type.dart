// pr_scanner: ignore-regression
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Identifies the type of actor performing a governance action.
///
/// Used in system_audit_log to distinguish between direct user actions,
/// impersonated actions, and automated system actions.
enum ActorType {
  human,
  impersonator,
  system;

  /// Database value (uppercase to match CHECK constraint).
  String get dbValue => name.toUpperCase();

  /// Parse from database string. Throws [IntegrityException] on invalid value.
  static ActorType fromString(String value) {
    return IntegrityException.shield(values, value.toLowerCase(), 'actor_type');
  }
}
