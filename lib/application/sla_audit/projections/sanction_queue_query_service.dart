import 'sanction_queue_item_view.dart';

/// Port: read-side query service for the sanction review queue.
///
/// Decouples the UI/provider layer from repository internals.
abstract class SanctionQueueQueryService {
  /// Returns all pending sanction items for the given organization.
  Future<List<SanctionQueueItemView>> listPending({
    required String organizationId,
  });

  /// Returns the count of pending sanction items.
  /// May delegate to a DB RPC for efficiency.
  Future<int> countPending({required String organizationId});
}
