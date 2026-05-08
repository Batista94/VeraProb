class QuotaAlertContext {
  final String orgId;
  final String orgName;
  final String resource;
  final int currentCount;
  final int maxAllowed;
  final List<String> adminEmails;

  const QuotaAlertContext({
    required this.orgId,
    required this.orgName,
    required this.resource,
    required this.currentCount,
    required this.maxAllowed,
    required this.adminEmails,
  });
}
