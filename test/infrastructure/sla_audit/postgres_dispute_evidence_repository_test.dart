import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_dispute_evidence_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// Pure-logic coverage for the evidence repo: the row decoder (verification
/// enum + UTC date parsing) and the client-side MIME guard that short-circuits
/// BEFORE a 10MB upload. The live storage/RPC path is integration-tested.
void main() {
  group('mapRow', () {
    final base = <String, dynamic>{
      'id': 'att-1',
      'organization_id': 'org-1',
      'queue_entry_id': 'queue-1',
      'storage_path': 'org-1/queue-1/file.png',
      'file_name': 'proof.png',
      'mime_type': 'image/png',
      'file_size_bytes': 2048,
      'sha256_hash': 'a' * 64,
      'verification_status': 'PENDING',
      'hash_verified_at': null,
      'uploaded_by': 'auditor-1',
      'attached_at': '2026-06-09T10:00:00.000Z',
      'deleted_at': null,
    };

    test('decodes a PENDING row with null lifecycle dates', () {
      final a = PostgresDisputeEvidenceRepository.mapRow(base);

      expect(a.id, 'att-1');
      expect(a.fileSizeBytes, 2048);
      expect(a.verificationStatus, EvidenceVerificationStatus.pending);
      expect(a.hashVerifiedAtUtc, isNull);
      expect(a.deletedAtUtc, isNull);
      expect(a.attachedAtUtc, DateTime.utc(2026, 6, 9, 10));
      expect(a.attachedAtUtc.isUtc, isTrue);
    });

    test('maps VERIFIED status + parses hash_verified_at as UTC (ADD-2)', () {
      final a = PostgresDisputeEvidenceRepository.mapRow(<String, dynamic>{
        ...base,
        'verification_status': 'VERIFIED',
        'hash_verified_at': '2026-06-09T11:30:00.000Z',
      });

      expect(a.verificationStatus, EvidenceVerificationStatus.verified);
      expect(a.hashVerifiedAtUtc, DateTime.utc(2026, 6, 9, 11, 30));
    });

    test('maps MISMATCH status (B2 tamper signal)', () {
      final a = PostgresDisputeEvidenceRepository.mapRow(<String, dynamic>{
        ...base,
        'verification_status': 'MISMATCH',
      });

      expect(a.verificationStatus, EvidenceVerificationStatus.mismatch);
    });

    test('parses a soft-deleted row (deleted_at present)', () {
      final a = PostgresDisputeEvidenceRepository.mapRow(<String, dynamic>{
        ...base,
        'deleted_at': '2026-06-10T08:00:00.000Z',
      });

      expect(a.deletedAtUtc, DateTime.utc(2026, 6, 10, 8));
    });
  });

  group('attach MIME guard', () {
    test('rejects a disallowed MIME before touching storage', () async {
      final repo = PostgresDisputeEvidenceRepository(_MockSupabaseClient());

      await expectLater(
        repo.attach(
          organizationId: 'org-1',
          queueEntryId: 'queue-1',
          fileName: 'evil.zip',
          mimeType: 'application/zip',
          sha256Hash: 'a' * 64,
          uploadedBy: 'auditor-1',
          fileBytes: Uint8List.fromList(const [1, 2, 3]),
          attachedAtUtc: DateTime.utc(2026, 6, 9, 10),
        ),
        throwsA(isA<IntegrityException>()),
      );
    });
  });
}
