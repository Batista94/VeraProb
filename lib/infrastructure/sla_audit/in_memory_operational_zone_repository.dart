import 'dart:collection';

import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/domain/sla_audit/operational_zone_repository.dart';

/// In-memory implementation of [OperationalZoneRepository].
///
/// Suitable for development and testing. Thread-safety is NOT guaranteed.
class InMemoryOperationalZoneRepository implements OperationalZoneRepository {
  final Map<String, OperationalZone> _store = {};

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async {
    // In-memory fake: CSV batch upsert is exercised against the Postgres RPC
    // (pgTAP). Here we only report the affected count for orchestration tests.
    return rows.length;
  }

  @override
  Future<void> save(OperationalZone zone) async {
    _store[zone.id] = zone;
  }

  @override
  Future<OperationalZone?> findById(
    String id, {
    required String organizationId,
  }) async {
    final zone = _store[id];
    if (zone == null || zone.organizationId != organizationId) return null;
    return zone;
  }

  @override
  Future<List<OperationalZone>> findByOrganization(
    String organizationId,
  ) async {
    final results =
        _store.values.where((z) => z.organizationId == organizationId).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return UnmodifiableListView(results);
  }
}
