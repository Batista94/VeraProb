import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/legal/legal_consent_status.dart';
import 'package:veraprob/domain/legal/legal_document.dart';

void main() {
  group('LegalConsentStatus', () {
    test('isPending and isCurrent getters work correctly', () {
      const pendingStatus = LegalConsentStatus(
        state: LegalConsentState.pending,
      );

      expect(pendingStatus.isPending, isTrue);
      expect(pendingStatus.isCurrent, isFalse);

      const currentStatus = LegalConsentStatus(
        state: LegalConsentState.current,
      );

      expect(currentStatus.isPending, isFalse);
      expect(currentStatus.isCurrent, isTrue);
    });

    test('holds document and priorVersion correctly', () {
      final doc = LegalDocument(
        id: 'doc-123',
        docType: 'terms_of_use',
        version: '1.0',
        title: 'Terms',
        bodyMarkdown: 'Content',
        contentSha256: 'sha',
        publishedAtUtc: DateTime.utc(2026, 1, 1),
      );

      final status = LegalConsentStatus(
        state: LegalConsentState.pending,
        document: doc,
        priorVersion: '0.9',
      );

      expect(status.document, equals(doc));
      expect(status.priorVersion, '0.9');
    });
  });
}
