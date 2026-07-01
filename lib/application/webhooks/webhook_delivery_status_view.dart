// WebhookDeliveryStatusView — Domain representation of webhook_delivery_status
//
// INV-13: Agnostic core. Maps from Supabase string.

enum WebhookDeliveryStatusView {
  pending,
  delivering,
  success,
  failed,
  dead;

  static WebhookDeliveryStatusView fromString(String value) {
    switch (value.toUpperCase()) {
      case 'PENDING':
        return WebhookDeliveryStatusView.pending;
      case 'DELIVERING':
        return WebhookDeliveryStatusView.delivering;
      case 'SUCCESS':
        return WebhookDeliveryStatusView.success;
      case 'FAILED':
        return WebhookDeliveryStatusView.failed;
      case 'DEAD':
        return WebhookDeliveryStatusView.dead;
      default:
        return WebhookDeliveryStatusView.pending;
    }
  }
}
