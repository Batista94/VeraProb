class QuotaAlertPayload {
  final String orgName;
  final String resource;
  final int usagePct;
  final int threshold;
  final int currentCount;
  final int maxAllowed;
  final List<String> recipientEmails;

  const QuotaAlertPayload({
    required this.orgName,
    required this.resource,
    required this.usagePct,
    required this.threshold,
    required this.currentCount,
    required this.maxAllowed,
    required this.recipientEmails,
  });
}
