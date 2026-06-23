import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/dispute_portal/portal_submission_audit_gateway.dart';

void main() {
  group('PortalSubmissionSummary.fromJson', () {
    test('parses a fully finalized PENDING_AUDIT row', () {
      final s = PortalSubmissionSummary.fromJson({
        'submission_id': 'sub-1',
        'attachment_id': 'att-1',
        'file_name': 'evidence.pdf',
        'mime_type_detected': 'application/pdf',
        'file_size_bytes_actual': 2048,
        'sha256_server': 'a' * 64,
        'status': 'PENDING_AUDIT',
        'submitted_at_utc': '2026-06-12T10:00:00Z',
        'finalized_at_utc': '2026-06-12T10:01:00Z',
      });

      expect(s.submissionId, 'sub-1');
      expect(s.attachmentId, 'att-1');
      expect(s.fileName, 'evidence.pdf');
      expect(s.fileSizeBytesActual, 2048);
      expect(s.sha256Server, 'a' * 64);
      expect(s.justificationText, isNull);
      expect(s.status, 'PENDING_AUDIT');
      expect(s.submittedAtUtc!.isUtc, isTrue);
      expect(s.finalizedAtUtc!.toIso8601String(), '2026-06-12T10:01:00.000Z');
    });

    test('parses the carrier testimony submitted with the file', () {
      final s = PortalSubmissionSummary.fromJson({
        'submission_id': 'sub-j',
        'attachment_id': 'att-j',
        'file_name': 'evidence.pdf',
        'mime_type_detected': 'application/pdf',
        'file_size_bytes_actual': 2048,
        'sha256_server': 'a' * 64,
        'justification_text': 'Contesto a multa: estava em fila autorizada.',
        'status': 'PENDING_AUDIT',
        'submitted_at_utc': '2026-06-12T10:00:00Z',
        'finalized_at_utc': '2026-06-12T10:01:00Z',
      });

      expect(
        s.justificationText,
        'Contesto a multa: estava em fila autorizada.',
      );
    });

    test('tolerates null attachment + timestamps (not yet joined)', () {
      final s = PortalSubmissionSummary.fromJson({
        'submission_id': 'sub-2',
        'attachment_id': null,
        'file_name': 'a.jpg',
        'mime_type_detected': null,
        'file_size_bytes_actual': null,
        'sha256_server': null,
        'status': 'PENDING_AUDIT',
        'submitted_at_utc': null,
        'finalized_at_utc': null,
      });

      expect(s.attachmentId, isNull);
      expect(s.mimeTypeDetected, isNull);
      expect(s.fileSizeBytesActual, isNull);
      expect(s.submittedAtUtc, isNull);
      expect(s.finalizedAtUtc, isNull);
    });

    test('Equatable identity holds for identical payloads', () {
      Map<String, dynamic> payload() => {
        'submission_id': 'sub-3',
        'attachment_id': 'att-3',
        'file_name': 'x.png',
        'mime_type_detected': 'image/png',
        'file_size_bytes_actual': 10,
        'sha256_server': 'b' * 64,
        'status': 'PENDING_AUDIT',
        'submitted_at_utc': '2026-06-12T10:00:00Z',
        'finalized_at_utc': '2026-06-12T10:01:00Z',
      };
      expect(
        PortalSubmissionSummary.fromJson(payload()),
        equals(PortalSubmissionSummary.fromJson(payload())),
      );
    });
  });

  group('PortalJustificationSummary.fromJson', () {
    test('parses a testimony-only contest row', () {
      final j = PortalJustificationSummary.fromJson({
        'justification_submission_id': 'pjs-1',
        'justification_text': 'Defesa textual sem anexo, porem detalhada.',
        'sha256_justification_seal': 'c' * 64,
        'status': 'PENDING_AUDIT',
        'submitted_at_utc': '2026-06-12T10:00:00Z',
      });

      expect(j.justificationSubmissionId, 'pjs-1');
      expect(j.justificationText, 'Defesa textual sem anexo, porem detalhada.');
      expect(j.sha256JustificationSeal, 'c' * 64);
      expect(j.status, 'PENDING_AUDIT');
      expect(j.submittedAtUtc!.isUtc, isTrue);
    });

    test('tolerates a null submitted_at_utc', () {
      final j = PortalJustificationSummary.fromJson({
        'justification_submission_id': 'pjs-2',
        'justification_text': 'Outra defesa textual valida.',
        'sha256_justification_seal': 'd' * 64,
        'status': 'PENDING_AUDIT',
        'submitted_at_utc': null,
      });

      expect(j.submittedAtUtc, isNull);
    });

    test('Equatable identity holds for identical payloads', () {
      Map<String, dynamic> payload() => {
        'justification_submission_id': 'pjs-3',
        'justification_text': 'Defesa textual equatable.',
        'sha256_justification_seal': 'e' * 64,
        'status': 'PENDING_AUDIT',
        'submitted_at_utc': '2026-06-12T10:00:00Z',
      };
      expect(
        PortalJustificationSummary.fromJson(payload()),
        equals(PortalJustificationSummary.fromJson(payload())),
      );
    });
  });
}
