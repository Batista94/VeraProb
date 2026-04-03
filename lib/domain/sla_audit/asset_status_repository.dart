import 'asset_status.dart';
import 'asset_status_event.dart';

/// Repository interface for [AssetStatusEvent] records.
///
/// Status is factEvent-sourced: [getCurrentStatus] replays events to derive
/// the current status. Writes are append-only (INV-1).
abstract class AssetStatusRepository {
  /// Returns the current [AssetStatus] of the given asset, derived by
  /// replaying all status events in chronological order.
  ///
  /// Returns [AssetStatus.active] if no events exist (default state).
  Future<AssetStatus> getCurrentStatus({
    required String assetId,
    required String organizationId,
  });

  /// Returns all status events for the given asset, ordered by
  /// [occurredAtUtc] ascending (INV-12).
  Future<List<AssetStatusEvent>> findByAsset({
    required String assetId,
    required String organizationId,
  });

  /// Appends a new status transition factEvent (INV-1: no update/delete).
  Future<void> append(AssetStatusEvent domainEvent);
}
