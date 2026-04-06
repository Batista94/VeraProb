import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';

/// Application service enforcing alert lifecycle transitions.
///
/// All mutations to alert status (ACTIVE → ACKNOWLEDGED → RESOLVED)
/// flow through this service. The OCC and repositories never perform
/// direct status modifications.
class AlertService {
  final OperationalAlertRepository _repo;

  AlertService({required OperationalAlertRepository repo}) : _repo = repo;

  /// Acknowledges an active alert.
  ///
  /// Validates: alert exists, is ACTIVE, valid transition.
  Future<void> acknowledge({
    required String alertId,
    required String userId,
    required DateTime atUtc,
  }) async {
    final alert = await _repo.findById(alertId);
    if (alert == null) {
      throw StateError('Alert not found: $alertId');
    }
    if (alert.status != 'ACTIVE') {
      throw StateError(
        'Cannot acknowledge alert in status "${alert.status}". '
        'Only ACTIVE alerts can be acknowledged.',
      );
    }

    final updated = alert.acknowledge(userId, atUtc);
    await _repo.update(updated);
  }

  /// Resolves an acknowledged alert.
  ///
  /// Validates: alert exists, is ACKNOWLEDGED, valid transition.
  Future<void> resolve({
    required String alertId,
    required DateTime atUtc,
  }) async {
    final alert = await _repo.findById(alertId);
    if (alert == null) {
      throw StateError('Alert not found: $alertId');
    }
    if (alert.status != 'ACKNOWLEDGED') {
      throw StateError(
        'Cannot resolve alert in status "${alert.status}". '
        'Only ACKNOWLEDGED alerts can be resolved.',
      );
    }

    final updated = alert.resolve(atUtc);
    await _repo.update(updated);
  }
}
