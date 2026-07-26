import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/telemetry_evidence.dart';
import 'package:veraprob/domain/sla_audit/telemetry_evidence_repository.dart';

/// In-memory implementation of [TelemetryEvidenceRepository].
///
/// Append-only by contract (INV-1): no update or delete operations exposed.
/// Enforces tenant isolation and duplicate content_hash detection in-memory.
///
/// Suitable for unit tests and simulation mode. The list is ordered by
/// insertion time (which mirrors [seq] ascending in the Postgres impl).
class InMemoryTelemetryEvidenceRepository
    implements TelemetryEvidenceRepository {
  // Keyed by contentHash for O(1) duplicate detection.
  final Map<String, TelemetryEvidence> _byContentHash = {};

  // Ordered list per (organizationId, setId) for findBySetId / findLatest.
  final Map<String, List<TelemetryEvidence>> _bySetKey = {};

  static String _setKey(String organizationId, String setId) =>
      '$organizationId|$setId';

  @override
  Future<void> save(TelemetryEvidence evidence) async {
    if (_byContentHash.containsKey(evidence.contentHash)) {
      // INV-10: typed domain exception — StateError is forbidden in repositories.
      throw IntegrityException(
        'Duplicate contentHash detected: ${evidence.contentHash}. '
        'TelemetryEvidence is append-only (INV-1).',
      );
    }
    _byContentHash[evidence.contentHash] = evidence;
    final key = _setKey(evidence.organizationId, evidence.setId);
    _bySetKey.putIfAbsent(key, () => []).add(evidence);
  }

  @override
  Future<List<TelemetryEvidence>> findBySetId(
    String setId, {
    required String organizationId,
  }) async {
    final key = _setKey(organizationId, setId);
    return List.unmodifiable(_bySetKey[key] ?? []);
  }

  @override
  Future<TelemetryEvidence?> findLatestBySetId(
    String setId, {
    required String organizationId,
  }) async {
    final key = _setKey(organizationId, setId);
    final chain = _bySetKey[key];
    if (chain == null || chain.isEmpty) return null;
    return chain.last;
  }
}
