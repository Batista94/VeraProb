import 'package:equatable/equatable.dart';

/// WebhookEndpointView — Application model (P2).
///
/// INV-13: Agnostic core representation of v_webhook_endpoint_health.
class WebhookEndpointView extends Equatable {
  final String id;
  final String url;
  final bool isActive;
  final DateTime? lastKickAt;
  final DateTime createdAt;
  final int totalLogs;
  final int pendingCount;
  final int deliveringCount;
  final int successCount;
  final int failedCount;
  final int deadCount;
  final DateTime? lastDispatchedAt;

  const WebhookEndpointView({
    required this.id,
    required this.url,
    required this.isActive,
    this.lastKickAt,
    required this.createdAt,
    required this.totalLogs,
    required this.pendingCount,
    required this.deliveringCount,
    required this.successCount,
    required this.failedCount,
    required this.deadCount,
    this.lastDispatchedAt,
  });

  // INV-13: factory method to map from infra map without exposing supabase types
  factory WebhookEndpointView.fromMap(Map<String, dynamic> map) {
    return WebhookEndpointView(
      id: map['id'] as String,
      url: map['url'] as String,
      isActive: map['is_active'] as bool,
      lastKickAt: map['last_kick_at'] != null
          ? DateTime.parse(map['last_kick_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      totalLogs: map['total_logs'] as int,
      pendingCount: map['pending_count'] as int,
      deliveringCount: map['delivering_count'] as int,
      successCount: map['success_count'] as int,
      failedCount: map['failed_count'] as int,
      deadCount: map['dead_count'] as int,
      lastDispatchedAt: map['last_dispatched_at'] != null
          ? DateTime.parse(map['last_dispatched_at'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [
    id,
    url,
    isActive,
    lastKickAt,
    createdAt,
    totalLogs,
    pendingCount,
    deliveringCount,
    successCount,
    failedCount,
    deadCount,
    lastDispatchedAt,
  ];
}
