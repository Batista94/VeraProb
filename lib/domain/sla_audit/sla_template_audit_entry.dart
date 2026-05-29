import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Immutable record of a single create/update to an SLA template (INV-3).
///
/// [templateSnapshot] is the full template state at the moment of change,
/// enabling retroactive governance without reconstructing diffs. Equality is
/// by [id] only — each entry is a distinct, append-only fact.
class SlaTemplateAuditEntry extends Equatable {
  static const allowedActions = {'CREATED', 'UPDATED'};

  final String id;
  final String organizationId;
  final String templateId;
  final String actorSessionId;
  final String action;
  final Map<String, dynamic> templateSnapshot;
  final DateTime occurredAtUtc;

  const SlaTemplateAuditEntry._({
    required this.id,
    required this.organizationId,
    required this.templateId,
    required this.actorSessionId,
    required this.action,
    required this.templateSnapshot,
    required this.occurredAtUtc,
  });

  /// Builds a validated entry. Throws [IntegrityException] (INV-10) on an
  /// unknown [action] or empty [organizationId]; stamps UTC via [clock] (INV-6).
  factory SlaTemplateAuditEntry.create({
    required String organizationId,
    required String templateId,
    required String actorSessionId,
    required String action,
    required Map<String, dynamic> templateSnapshot,
    required IDateTimeProvider clock,
  }) {
    if (!allowedActions.contains(action)) {
      throw IntegrityException(
        'Unknown SLA template audit action "$action"',
        field: 'action',
      );
    }
    if (organizationId.isEmpty) {
      throw const IntegrityException(
        'organizationId must not be empty',
        field: 'organizationId',
      );
    }
    return SlaTemplateAuditEntry._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      templateId: templateId,
      actorSessionId: actorSessionId,
      action: action,
      templateSnapshot: templateSnapshot,
      occurredAtUtc: clock.nowUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'organization_id': organizationId,
    'template_id': templateId,
    'actor_session_id': actorSessionId,
    'action': action,
    'template_snapshot': templateSnapshot,
    'occurred_at_utc': occurredAtUtc.toIso8601String(),
  };

  @override
  List<Object?> get props => [id];
}
