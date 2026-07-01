abstract class IWebhookDispatcherPort {
  /// Dispatches the sealed verdict webhook using a fire-and-forget mechanism.
  /// Should not block the main application flow (Happy Path).
  Future<void> dispatchVerdictWebhooks({required String organizationId});
}
