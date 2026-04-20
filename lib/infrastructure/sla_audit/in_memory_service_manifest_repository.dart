import 'dart:collection';

import 'package:veraprob/domain/sla_audit/service_manifest.dart';
import 'package:veraprob/domain/sla_audit/service_manifest_repository.dart';

/// In-memory implementation of [ServiceManifestRepository].
///
/// Suitable for development and testing.
class InMemoryServiceManifestRepository implements ServiceManifestRepository {
  final Map<String, ServiceManifest> _store = {};

  @override
  Future<void> save(ServiceManifest manifest) async {
    _store[manifest.id] = manifest;
  }

  @override
  Future<List<ServiceManifest>> findByContract(
    String contractId, {
    required String organizationId,
  }) async {
    final results =
        _store.values
            .where(
              (m) =>
                  m.organizationId == organizationId &&
                  m.contractId == contractId,
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return UnmodifiableListView(results);
  }

  @override
  Future<ServiceManifest?> findById(
    String id, {
    required String organizationId,
  }) async {
    final manifest = _store[id];
    if (manifest != null && manifest.organizationId == organizationId) {
      return manifest;
    }
    return null;
  }

  @override
  Future<void> delete(String id, {required String organizationId}) async {
    final manifest = _store[id];
    if (manifest != null && manifest.organizationId == organizationId) {
      _store.remove(id);
    }
  }
}
