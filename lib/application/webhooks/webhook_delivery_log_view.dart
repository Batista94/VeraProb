import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';

part 'webhook_delivery_log_view.freezed.dart';

/// WebhookDeliveryLogView — Application model (P2).
///
/// INV-13: Agnostic core representation of webhook_delivery_logs.
@freezed
class WebhookDeliveryLogView with _$WebhookDeliveryLogView {
  const factory WebhookDeliveryLogView({
    required String id,
    required String endpointId,
    required String eventType,
    required Map<String, dynamic> payload,
    required WebhookDeliveryStatusView status,
    required int attemptCount,
    DateTime? nextAttemptAt,
    String? lastError,
    String? signature,
    DateTime? dispatchedAt,
    required DateTime createdAt,
    required String ledgerEntryId,
  }) = _WebhookDeliveryLogView;

  // INV-13: factory method to map from infra map
  factory WebhookDeliveryLogView.fromMap(Map<String, dynamic> map) {
    return WebhookDeliveryLogView(
      id: map['id'] as String,
      endpointId: map['endpoint_id'] as String,
      eventType: map['event_type'] as String,
      payload: map['payload'] as Map<String, dynamic>,
      status: WebhookDeliveryStatusView.fromString(map['status'] as String),
      attemptCount: map['attempt_count'] as int,
      nextAttemptAt: map['next_attempt_at'] != null ? DateTime.parse(map['next_attempt_at'] as String) : null,
      lastError: map['last_error'] as String?,
      signature: map['signature'] as String?,
      dispatchedAt: map['dispatched_at'] != null ? DateTime.parse(map['dispatched_at'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      ledgerEntryId: map['ledger_entry_id'] as String,
    );
  }
}
