import 'package:veraprob/domain/sla_audit/spoofing_audit_entry.dart';
import 'package:veraprob/domain/sla_audit/spoofing_audit_repository.dart';

/// In-memory implementation of [SpoofingAuditRepository] for tests.
class InMemorySpoofingAuditRepository implements SpoofingAuditRepository {
  final List<SpoofingAuditEntry> _entries = [];

  List<SpoofingAuditEntry> get entries => List.unmodifiable(_entries);

  @override
  Future<void> append(SpoofingAuditEntry entry) async {
    if (_entries.any((e) => e.id == entry.id)) {
      throw Exception('Duplicate entry ID: ${entry.id}');
    }
    _entries.add(entry);
  }

  @override
  Future<SpoofingAuditEntry?> getById(String id) async {
    final results = _entries.where((e) => e.id == id);
    return results.isNotEmpty ? results.first : null;
  }

  @override
  Future<List<SpoofingAuditEntry>> getPendingReview(
    String organizationId,
  ) async {
    return _entries
        .where(
          (e) => e.organizationId == organizationId && e.reviewedAt == null,
        )
        .toList();
  }

  @override
  Future<List<SpoofingAuditEntry>> getByDevice(
    String organizationId,
    String deviceId, {
    DateTime? from,
    DateTime? to,
  }) async {
    return _entries.where((e) {
      if (e.organizationId != organizationId || e.deviceId != deviceId) {
        return false;
      }
      if (from != null && e.windowStart.isBefore(from)) return false;
      if (to != null && e.windowEnd.isAfter(to)) return false;
      return true;
    }).toList();
  }
}
