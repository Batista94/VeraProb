import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_dispute_evidence_repository.dart';

void main() {
  late InMemoryDisputeEvidenceRepository repo;
  final bytes = Uint8List.fromList(List.filled(128, 7));
  final hash = 'a' * 64;
  final attachedAt = DateTime.utc(2026, 6, 9, 10);

  setUp(() => repo = InMemoryDisputeEvidenceRepository());

  Future<DisputeEvidenceAttachment> attach({
    String org = 'org-1',
    String queue = 'queue-1',
    String mime = 'image/png',
    String sha = '',
  }) {
    return repo.attach(
      organizationId: org,
      queueEntryId: queue,
      fileName: 'proof.png',
      mimeType: mime,
      sha256Hash: sha.isEmpty ? hash : sha,
      uploadedBy: 'auditor-1',
      fileBytes: bytes,
      attachedAtUtc: attachedAt,
    );
  }

  group('attach', () {
    test(
      'seals a PENDING attachment with synthesized path + byte size',
      () async {
        final a = await attach();

        expect(a.verificationStatus, EvidenceVerificationStatus.pending);
        expect(a.fileSizeBytes, 128);
        expect(a.storagePath, startsWith('org-1/queue-1/'));
        expect(a.storagePath, endsWith('.png'));
        expect(a.deletedAtUtc, isNull);
      },
    );

    test('rejects a disallowed MIME at the seal boundary (INV-9)', () async {
      await expectLater(
        attach(mime: 'application/zip'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('rejects a malformed SHA-256 seal (INV-9)', () async {
      await expectLater(
        attach(sha: 'not-a-hash'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test(
      'enforces the 10-attachment cap (ADD-3) → IntegrityException',
      () async {
        for (var i = 0; i < 10; i++) {
          await repo.attach(
            organizationId: 'org-1',
            queueEntryId: 'queue-1',
            fileName: 'p$i.png',
            mimeType: 'image/png',
            // distinct hashes — uq seal per queue (mirrors the DB unique).
            sha256Hash: '${i.toString().padLeft(2, '0')}${'a' * 62}',
            uploadedBy: 'auditor-1',
            fileBytes: bytes,
            attachedAtUtc: attachedAt,
          );
        }

        await expectLater(attach(), throwsA(isA<IntegrityException>()));
      },
    );
  });

  group('findByQueueEntryId / countActive', () {
    test('scopes to org + queue and excludes soft-deleted', () async {
      final a = await attach();
      await attach(queue: 'queue-2');
      await attach(org: 'org-2');

      expect(
        await repo.countActiveByQueueEntryId(
          organizationId: 'org-1',
          queueEntryId: 'queue-1',
        ),
        1,
      );

      await repo.softDelete(
        organizationId: 'org-1',
        attachmentId: a.id,
        deletedAtUtc: DateTime.utc(2026, 6, 9, 12),
      );

      final active = await repo.findByQueueEntryId(
        organizationId: 'org-1',
        queueEntryId: 'queue-1',
      );
      expect(active, isEmpty);
    });
  });

  group('softDelete', () {
    test(
      'cross-org delete is indistinguishable from not-found (INV-26)',
      () async {
        final a = await attach();

        await expectLater(
          repo.softDelete(
            organizationId: 'org-2',
            attachmentId: a.id,
            deletedAtUtc: DateTime.utc(2026, 6, 9, 12),
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );
  });
}
