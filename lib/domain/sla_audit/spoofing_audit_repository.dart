import 'spoofing_audit_entry.dart';

/// Repository interface for append-only spoofing audit logs.
///
/// Implements INV-21: Audit logs must be append-only with no deletion.
abstract class SpoofingAuditRepository {
  /// Appends a new entry to the audit log.
  /// Throws if an entry with the same ID already exists.
  Future<void> append(SpoofingAuditEntry entry);

  /// Fetches an entry by ID.
  Future<SpoofingAuditEntry?> getById(String id);

  /// Fetches all entries pending review for a given organization.
  Future<List<SpoofingAuditEntry>> getPendingReview(String organizationId);

  /// Fetches all entries for a specific device window.
  Future<List<SpoofingAuditEntry>> getByDevice(
    String organizationId,
    String deviceId, {
    DateTime? from,
    DateTime? to,
  });
}
