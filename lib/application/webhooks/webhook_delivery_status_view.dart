// WebhookDeliveryStatusView — Domain representation of webhook_delivery_status
//
// INV-13: Agnostic core. Maps from Supabase string.

enum WebhookDeliveryStatusView {
  pending,
  delivering,
  success,
  failed,
  dead;

  /// Rótulo PT para a UI (evita vazamento do name técnico em inglês).
  String get labelPt {
    switch (this) {
      case WebhookDeliveryStatusView.pending:
        return 'Pendente';
      case WebhookDeliveryStatusView.delivering:
        return 'Enviando';
      case WebhookDeliveryStatusView.success:
        return 'Sucesso';
      case WebhookDeliveryStatusView.failed:
        return 'Falha';
      case WebhookDeliveryStatusView.dead:
        return 'Esgotado';
    }
  }

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
