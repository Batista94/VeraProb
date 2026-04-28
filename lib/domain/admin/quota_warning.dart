import 'package:equatable/equatable.dart';

/// Represents a soft quota warning for an organization resource.
///
/// Emitted at 50%, 80%, 90%, and 99% usage thresholds.
/// Does NOT block operations — purely informational for dashboard display.
class QuotaWarning extends Equatable {
  final int id;
  final String organizationId;
  final String resource;
  final int usagePct;
  final int threshold;
  final int currentCount;
  final int maxAllowed;
  final DateTime triggeredAt;

  const QuotaWarning({
    required this.id,
    required this.organizationId,
    required this.resource,
    required this.usagePct,
    required this.threshold,
    required this.currentCount,
    required this.maxAllowed,
    required this.triggeredAt,
  });

  /// Whether this warning is critical (>= 90%).
  bool get isCritical => threshold >= 90;

  /// Whether this warning is urgent (>= 80%).
  bool get isUrgent => threshold >= 80;

  factory QuotaWarning.fromJson(Map<String, dynamic> json) {
    return QuotaWarning(
      id: json['id'] as int,
      organizationId: json['organization_id'] as String,
      resource: json['resource'] as String,
      usagePct: json['usage_pct'] as int,
      threshold: json['threshold'] as int,
      currentCount: json['current_count'] as int,
      maxAllowed: json['max_allowed'] as int,
      triggeredAt: DateTime.parse(json['triggered_at'] as String).toUtc(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    resource,
    usagePct,
    threshold,
    currentCount,
    maxAllowed,
    triggeredAt,
  ];
}
