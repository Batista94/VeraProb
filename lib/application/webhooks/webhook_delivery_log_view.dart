import 'package:equatable/equatable.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';

/// WebhookDeliveryLogView — Application model (P2).
///
/// INV-13: Agnostic core representation of webhook_delivery_logs.
class WebhookDeliveryLogView extends Equatable {
  final String id;
  final String endpointId;
  final String eventType;
  final Map<String, dynamic> payload;
  final WebhookDeliveryStatusView status;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final String? signature;
  final DateTime? dispatchedAt;
  final DateTime createdAt;
  final String ledgerEntryId;

  const WebhookDeliveryLogView({
    required this.id,
    required this.endpointId,
    required this.eventType,
    required this.payload,
    required this.status,
    required this.attemptCount,
    this.nextAttemptAt,
    this.lastError,
    this.signature,
    this.dispatchedAt,
    required this.createdAt,
    required this.ledgerEntryId,
  });

  // INV-13: factory method to map from infra map
  factory WebhookDeliveryLogView.fromMap(Map<String, dynamic> map) {
    return WebhookDeliveryLogView(
      id: map['id'] as String,
      endpointId: map['endpoint_id'] as String,
      eventType: map['event_type'] as String,
      payload: map['payload'] as Map<String, dynamic>,
      status: WebhookDeliveryStatusView.fromString(map['status'] as String),
      attemptCount: map['attempt_count'] as int,
      nextAttemptAt: map['next_attempt_at'] != null
          ? DateTime.parse(map['next_attempt_at'] as String)
          : null,
      lastError: map['last_error'] as String?,
      signature: map['signature'] as String?,
      dispatchedAt: map['dispatched_at'] != null
          ? DateTime.parse(map['dispatched_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      ledgerEntryId: map['ledger_entry_id'] as String,
    );
  }

  @override
  List<Object?> get props => [
    id,
    endpointId,
    eventType,
    payload,
    status,
    attemptCount,
    nextAttemptAt,
    lastError,
    signature,
    dispatchedAt,
    createdAt,
    ledgerEntryId,
  ];
}
