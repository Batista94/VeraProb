// pr_scanner: ignore-regression — PR elevation org-scope ports / domain touch (Council-approved plan)
import 'operational_alert.dart';

/// Repository interface for operational alerts.
///
/// Supports creation, active queries, and entity lookup.
/// Lifecycle mutations (acknowledge, resolve) are controlled
/// exclusively through [AlertService] — not exposed here.
abstract class OperationalAlertRepository {
  /// Persists a new alert. Returns the generated UUID.
  /// Database UNIQUE constraint on (triggering_event_id, alert_type)
  /// enforces idempotency.
  Future<String> save(OperationalAlert alert);

  /// Retrieves all active alerts for a given organization.
  Future<List<OperationalAlert>> findActive(String organizationId);

  /// Retrieves all alerts for a given entity (SET ID), org-scoped (INV-1).
  Future<List<OperationalAlert>> findByEntityId(
    String entityId, {
    required String organizationId,
  });

  /// Retrieves a single alert by ID, org-scoped (INV-1/INV-26).
  Future<OperationalAlert?> findById(
    String alertId, {
    required String organizationId,
  });

  /// Updates the status and audit fields of an existing alert.
  /// Used exclusively by AlertService for lifecycle transitions.
  Future<void> update(OperationalAlert alert);

  /// Marks an alert as viewed by [userId] (collision awareness).
  /// Idempotent: no-op if user already in viewed_by_user_ids.
  Future<void> markViewed(String alertId, String userId);
}
