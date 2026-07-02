class WebhookApplicationException implements Exception {
  final String message;
  const WebhookApplicationException(this.message);

  @override
  String toString() => message;
}
