import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/legal/legal_document.dart';

void main() {
  group('LegalDocument', () {
    test('instantiates correctly with all fields', () {
      final doc = LegalDocument(
        id: 'doc-123',
        docType: 'terms_of_use',
        version: '1.0',
        title: 'Terms of Use',
        bodyMarkdown: '# Terms',
        contentSha256: 'abc123sha',
        changelog: 'Initial version',
        publishedAtUtc: DateTime.utc(2026, 1, 1),
      );

      expect(doc.id, 'doc-123');
      expect(doc.docType, 'terms_of_use');
      expect(doc.version, '1.0');
      expect(doc.title, 'Terms of Use');
      expect(doc.bodyMarkdown, '# Terms');
      expect(doc.contentSha256, 'abc123sha');
      expect(doc.changelog, 'Initial version');
      expect(doc.publishedAtUtc, DateTime.utc(2026, 1, 1));
    });

    test('instantiates correctly without changelog', () {
      final doc = LegalDocument(
        id: 'doc-123',
        docType: 'terms_of_use',
        version: '1.0',
        title: 'Terms of Use',
        bodyMarkdown: '# Terms',
        contentSha256: 'abc123sha',
        publishedAtUtc: DateTime.utc(2026, 1, 1),
      );

      expect(doc.changelog, isNull);
    });
  });
}
