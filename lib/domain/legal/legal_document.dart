// pr_scanner: ignore-regression — Legal Gate LGPD document VO (Council-approved package)
/// Published legal document version (LGPD SSOT row).
class LegalDocument {
  final String id;
  final String docType;
  final String version;
  final String title;
  final String bodyMarkdown;
  final String contentSha256;
  final String? changelog;
  final DateTime publishedAtUtc;

  const LegalDocument({
    required this.id,
    required this.docType,
    required this.version,
    required this.title,
    required this.bodyMarkdown,
    required this.contentSha256,
    this.changelog,
    required this.publishedAtUtc,
  });
}
