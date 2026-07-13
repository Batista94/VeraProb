import 'package:veraprob/domain/shared/integrity_exception.dart';
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
  /// Validates: alert exists (org-scoped), is ACTIVE, valid transition.
  Future<void> acknowledge({
    required String alertId,
    required String organizationId,
    required String userId,
    required DateTime atUtc,
  }) async {
    final alert = await _repo.findById(alertId, organizationId: organizationId);
    if (alert == null) {
      throw const IntegrityException('Alert not found', field: 'alertId');
    }
    if (alert.status != 'ACTIVE') {
      throw IntegrityException(
        'Cannot acknowledge alert in status "${alert.status}". '
        'Only ACTIVE alerts can be acknowledged.',
        field: 'status',
      );
    }

    final updated = alert.acknowledge(userId, atUtc);
    await _repo.update(updated);
  }

  /// Resolves an acknowledged alert.
  ///
  /// Validates: alert exists (org-scoped), is ACKNOWLEDGED, valid transition.
  Future<void> resolve({
    required String alertId,
    required String organizationId,
    required DateTime atUtc,
  }) async {
    final alert = await _repo.findById(alertId, organizationId: organizationId);
    if (alert == null) {
      throw const IntegrityException('Alert not found', field: 'alertId');
    }
    if (alert.status != 'ACKNOWLEDGED') {
      throw IntegrityException(
        'Cannot resolve alert in status "${alert.status}". '
        'Only ACKNOWLEDGED alerts can be resolved.',
        field: 'status',
      );
    }

    final updated = alert.resolve(atUtc);
    await _repo.update(updated);
  }
}
