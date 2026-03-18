import '../../domain/sla_audit/asset_status.dart';
import '../../domain/sla_audit/asset_status_event.dart';
import '../../domain/sla_audit/asset_status_repository.dart';

class InMemoryAssetStatusRepository implements AssetStatusRepository {
  // Ordered list of events per (organizationId, assetId)
  final Map<String, List<AssetStatusEvent>> _events = {};

  static String _key(String organizationId, String assetId) =>
      '$organizationId|$assetId';

  @override
  Future<void> append(AssetStatusEvent event) async {
    final key = _key(event.organizationId, event.assetId);
    _events.putIfAbsent(key, () => []).add(event);
  }

  @override
  Future<List<AssetStatusEvent>> findByAsset({
    required String assetId,
    required String organizationId,
  }) async {
    final key = _key(organizationId, assetId);
    final events = List<AssetStatusEvent>.from(_events[key] ?? []);
    events.sort((a, b) => a.occurredAtUtc.compareTo(b.occurredAtUtc));
    return events;
  }

  @override
  Future<AssetStatus> getCurrentStatus({
    required String assetId,
    required String organizationId,
  }) async {
    final events = await findByAsset(
      assetId: assetId,
      organizationId: organizationId,
    );
    if (events.isEmpty) return AssetStatus.active; // default
    return events.last.newStatus;
  }
}
