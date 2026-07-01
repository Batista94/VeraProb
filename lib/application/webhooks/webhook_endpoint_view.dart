import 'package:freezed_annotation/freezed_annotation.dart';

part 'webhook_endpoint_view.freezed.dart';

/// WebhookEndpointView — Application model (P2).
///
/// INV-13: Agnostic core representation of v_webhook_endpoint_health.
@freezed
class WebhookEndpointView with _$WebhookEndpointView {
  const factory WebhookEndpointView({
    required String id,
    required String url,
    required bool isActive,
    DateTime? lastKickAt,
    required DateTime createdAt,
    required int totalLogs,
    required int pendingCount,
    required int deliveringCount,
    required int successCount,
    required int failedCount,
    required int deadCount,
    DateTime? lastDispatchedAt,
  }) = _WebhookEndpointView;

  // INV-13: factory method to map from infra map without exposing supabase types
  factory WebhookEndpointView.fromMap(Map<String, dynamic> map) {
    return WebhookEndpointView(
      id: map['id'] as String,
      url: map['url'] as String,
      isActive: map['is_active'] as bool,
      lastKickAt: map['last_kick_at'] != null ? DateTime.parse(map['last_kick_at'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      totalLogs: map['total_logs'] as int,
      pendingCount: map['pending_count'] as int,
      deliveringCount: map['delivering_count'] as int,
      successCount: map['success_count'] as int,
      failedCount: map['failed_count'] as int,
      deadCount: map['dead_count'] as int,
      lastDispatchedAt: map['last_dispatched_at'] != null ? DateTime.parse(map['last_dispatched_at'] as String) : null,
    );
  }
}
