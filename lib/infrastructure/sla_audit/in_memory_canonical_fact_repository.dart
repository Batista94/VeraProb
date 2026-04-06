import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact_repository.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';

class InMemoryCanonicalFactRepository implements CanonicalFactRepository {
  final List<CanonicalFact> _facts = [];

  @override
  Future<void> save(CanonicalFact fact) async {
    _facts.add(fact);
  }

  @override
  Future<List<CanonicalFact>> findByAssetInWindow({
    required String assetId,
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
    bool includeAllFlags = false,
  }) async {
    return _facts
        .where(
          (f) =>
              f.organizationId == organizationId &&
              f.assetId == assetId &&
              !f.gpsTimestamp.isBefore(fromUtc) &&
              !f.gpsTimestamp.isAfter(toUtc) &&
              (includeAllFlags || f.isEligibleForEvaluation),
        )
        .toList()
      ..sort((a, b) => a.gpsTimestamp.compareTo(b.gpsTimestamp));
  }

  @override
  Future<List<CanonicalFact>> findByDeviceChronological({
    required String deviceId,
    required String organizationId,
    DateTime? sinceUtc,
  }) async {
    return _facts
        .where(
          (f) =>
              f.organizationId == organizationId &&
              f.deviceId == deviceId &&
              (sinceUtc == null || f.gpsTimestamp.isAfter(sinceUtc)),
        )
        .toList()
      ..sort((a, b) => a.gpsTimestamp.compareTo(b.gpsTimestamp));
  }

  @override
  Future<Map<IngestionIntegrityFlag, int>> countByIntegrityFlag({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final result = <IngestionIntegrityFlag, int>{};
    for (final f in _facts) {
      if (f.organizationId != organizationId) continue;
      if (f.gpsTimestamp.isBefore(fromUtc) || f.gpsTimestamp.isAfter(toUtc)) {
        continue;
      }
      result[f.integrityFlag] = (result[f.integrityFlag] ?? 0) + 1;
    }
    return result;
  }

  List<CanonicalFact> get all => List.unmodifiable(_facts);
  void clear() => _facts.clear();
}
