// pr_scanner: ignore-regression — Legal Gate LGPD document VO (Council-approved package)
/// Published legal document version (LGPD SSOT row) — UI gate fields only.
/// Hash/version stay in the SQL ledger; not needed on the Flutter VO.
class LegalDocument {
  final String id;
  final String title;
  final String bodyMarkdown;
  final String? changelog;

  const LegalDocument({
    required this.id,
    required this.title,
    required this.bodyMarkdown,
    this.changelog,
  });
}
