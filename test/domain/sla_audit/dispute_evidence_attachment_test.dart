import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  const validHash =
      'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

  DisputeEvidenceAttachment build({
    String sha256Hash = validHash,
    int fileSizeBytes = 2048,
    String mimeType = 'image/jpeg',
    DateTime? attachedAtUtc,
    String id = 'att-1',
  }) {
    return DisputeEvidenceAttachment.validated(
      id: id,
      organizationId: 'org-1',
      queueEntryId: 'queue-1',
      storagePath: 'org-1/queue-1/photo.jpg',
      fileName: 'photo.jpg',
      mimeType: mimeType,
      fileSizeBytes: fileSizeBytes,
      sha256Hash: sha256Hash,
      verificationStatus: EvidenceVerificationStatus.pending,
      hashVerifiedAtUtc: null,
      uploadedBy: 'user-1',
      attachedAtUtc: attachedAtUtc ?? DateTime.utc(2026, 8, 13, 12),
      deletedAtUtc: null,
    );
  }

  group('DisputeEvidenceAttachment.validated', () {
    test('constructs a valid attachment (happy path)', () {
      final attachment = build();
      expect(attachment.sha256Hash, validHash);
      expect(attachment.verificationStatus, EvidenceVerificationStatus.pending);
    });

    // T1
    test('rejects a malformed SHA-256 hash (INV-9)', () {
      expect(
        () => build(sha256Hash: 'NOT-A-VALID-HASH'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('rejects an uppercase hash (lowercase hex only, INV-9)', () {
      expect(
        () => build(sha256Hash: validHash.toUpperCase()),
        throwsA(isA<IntegrityException>()),
      );
    });

    // T2
    test('rejects a non-positive file size', () {
      expect(() => build(fileSizeBytes: 0), throwsA(isA<IntegrityException>()));
    });

    // T3
    test('rejects a file larger than 10MB', () {
      expect(
        () => build(fileSizeBytes: 10485761),
        throwsA(isA<IntegrityException>()),
      );
    });

    // T4
    test('rejects a MIME type outside the catalogue', () {
      expect(
        () => build(mimeType: 'application/zip'),
        throwsA(isA<IntegrityException>()),
      );
    });

    // T5
    test('rejects a non-UTC attachedAt (INV-6)', () {
      expect(
        () => build(attachedAtUtc: DateTime(2026, 8, 13, 12)),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  group('DisputeEvidenceAttachment equality', () {
    // T5b: same id but different hash ⇒ NOT equal (anti hash-swap in sets).
    test('same id + different hash are NOT equal', () {
      final a = build();
      final b = build(
        sha256Hash:
            'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      );
      expect(a == b, isFalse);
    });

    test('identical structural fields are equal', () {
      expect(build() == build(), isTrue);
    });
  });
}
