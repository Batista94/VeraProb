/// INV-6: naive Postgres timestamps (no Z / offset) are treated as UTC.
DateTime parsePostgresUtc(Object? raw) {
  final s = raw as String;
  final normalized = (s.endsWith('Z') || s.contains('+')) ? s : '${s}Z';
  return DateTime.parse(normalized).toUtc();
}
