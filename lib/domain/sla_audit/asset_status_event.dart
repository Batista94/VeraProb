import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'asset_status.dart';
import 'domain_exception.dart';

/// Domain entity representing a single asset status transition.
///
/// Status is event-sourced — the current status of an asset is determined
/// by replaying these events in [occurredAtUtc] order (INV-12).
///
/// **Invariants:**
/// - INV-1: Append-only. Status events are never deleted or mutated.
/// - INV-3: [occurredAtUtc] must be UTC.
/// - INV-6: [organizationId] on every record.
class AssetStatusEvent extends Equatable {
  final String id;
  final String organizationId;
  final String assetId;
  final AssetStatus newStatus;
  final AssetStatus previousStatus;

  /// UTC timestamp of the status transition.
  final DateTime occurredAtUtc;

  /// Optional human-readable reason (e.g., "Preventive maintenance - 30k km").
  final String? reason;

  /// User or system that triggered the transition.
  final String triggeredBy;

  const AssetStatusEvent._({
    required this.id,
    required this.organizationId,
    required this.assetId,
    required this.newStatus,
    required this.previousStatus,
    required this.occurredAtUtc,
    this.reason,
    required this.triggeredBy,
  });

  factory AssetStatusEvent.create({
    required String organizationId,
    required String assetId,
    required AssetStatus newStatus,
    required AssetStatus previousStatus,
    required DateTime occurredAtUtc,
    String? reason,
    required String triggeredBy,
  }) {
    if (organizationId.isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    if (assetId.isEmpty) {
      throw const DomainException('assetId must not be empty');
    }
    if (triggeredBy.isEmpty) {
      throw const DomainException('triggeredBy must not be empty');
    }
    if (!occurredAtUtc.isUtc) {
      throw const DomainException(
        'occurredAtUtc must be UTC (INV-3). Call .toUtc() before passing.',
      );
    }
    if (newStatus == previousStatus) {
      throw const DomainException(
        'newStatus must differ from previousStatus — no-op transitions are not recorded',
      );
    }

    return AssetStatusEvent._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      assetId: assetId,
      newStatus: newStatus,
      previousStatus: previousStatus,
      occurredAtUtc: occurredAtUtc,
      reason: reason,
      triggeredBy: triggeredBy,
    );
  }

  factory AssetStatusEvent.reconstitute({
    required String id,
    required String organizationId,
    required String assetId,
    required AssetStatus newStatus,
    required AssetStatus previousStatus,
    required DateTime occurredAtUtc,
    String? reason,
    required String triggeredBy,
  }) {
    return AssetStatusEvent._(
      id: id,
      organizationId: organizationId,
      assetId: assetId,
      newStatus: newStatus,
      previousStatus: previousStatus,
      occurredAtUtc: occurredAtUtc,
      reason: reason,
      triggeredBy: triggeredBy,
    );
  }

  @override
  List<Object?> get props => [id];
}
