import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';

/// In-memory implementation of [OperationalAlertRepository] for testing.
class InMemoryOperationalAlertRepository implements OperationalAlertRepository {
  final List<OperationalAlert> _alerts = [];
  static const _uuid = Uuid();

  /// Exposes all stored alerts for test assertions.
  List<OperationalAlert> get alerts => List.unmodifiable(_alerts);

  @override
  Future<String> save(OperationalAlert alert) async {
    final id = _uuid.v4();
    // Enforce idempotency: (triggering_event_id, alert_type) must be unique
    final duplicate = _alerts.any(
      (a) =>
          a.triggeringEventId == alert.triggeringEventId &&
          a.alertType == alert.alertType &&
          alert.triggeringEventId != null,
    );
    if (duplicate) return id; // Silently ignore duplicate

    _alerts.add(
      OperationalAlert(
        id: id,
        organizationId: alert.organizationId,
        entityId: alert.entityId,
        contractId: alert.contractId,
        alertType: alert.alertType,
        severity: alert.severity,
        triggeredAtUtc: alert.triggeredAtUtc,
        triggeringEventId: alert.triggeringEventId,
        traceId: alert.traceId,
        context: alert.context,
        status: alert.status,
      ),
    );
    return id;
  }

  @override
  Future<List<OperationalAlert>> findActive(String organizationId) async {
    return _alerts
        .where(
          (a) => a.organizationId == organizationId && a.status == 'ACTIVE',
        )
        .toList()
      ..sort((a, b) {
        final severityOrder = _severityRank(
          a.severity,
        ).compareTo(_severityRank(b.severity));
        if (severityOrder != 0) return severityOrder;
        return b.triggeredAtUtc.compareTo(a.triggeredAtUtc);
      });
  }

  @override
  Future<List<OperationalAlert>> findByEntityId(String entityId) async {
    return _alerts.where((a) => a.entityId == entityId).toList()
      ..sort((a, b) => b.triggeredAtUtc.compareTo(a.triggeredAtUtc));
  }

  @override
  Future<OperationalAlert?> findById(String alertId) async {
    final matches = _alerts.where((a) => a.id == alertId);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<void> update(OperationalAlert alert) async {
    final index = _alerts.indexWhere((a) => a.id == alert.id);
    if (index >= 0) {
      _alerts[index] = alert;
    }
  }

  int _severityRank(String severity) {
    switch (severity) {
      case 'CRITICAL':
        return 0;
      case 'HIGH':
        return 1;
      case 'WARNING':
        return 2;
      default:
        return 3;
    }
  }
}
