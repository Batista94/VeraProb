abstract class IQuotaAlertStateCache {
  Future<bool> wasAlertSent({
    required String orgId,
    required String resource,
    required int threshold,
  });

  Future<void> markAlertSent({
    required String orgId,
    required String resource,
    required int threshold,
  });
}
