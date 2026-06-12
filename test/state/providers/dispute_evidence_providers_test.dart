import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/dispute_evidence_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';

const _qid = 'queue-001';

class _FixedClock implements IDateTimeProvider {
  final DateTime _now;
  _FixedClock(this._now);
  @override
  DateTime nowUtc() => _now;
  @override
  DateTime nowBrazil() => _now;
}

class _CapturingRepo implements DisputeEvidenceRepository {
  String? lastHash;
  Uint8List? lastBytes;
  String? lastFileName;
  String? lastMime;
  int softDeleteCalls = 0;
  String? lastDeletedId;

  @override
  Future<DisputeEvidenceAttachment> attach({
    required String organizationId,
    required String queueEntryId,
    required String fileName,
    required String mimeType,
    required String sha256Hash,
    required String uploadedBy,
    required Uint8List fileBytes,
    required DateTime attachedAtUtc,
  }) async {
    lastHash = sha256Hash;
    lastBytes = fileBytes;
    lastFileName = fileName;
    lastMime = mimeType;
    return DisputeEvidenceAttachment(
      id: 'new-id',
      organizationId: organizationId,
      queueEntryId: queueEntryId,
      storagePath: 'p',
      fileName: fileName,
      mimeType: mimeType,
      fileSizeBytes: fileBytes.length,
      sha256Hash: sha256Hash,
      verificationStatus: EvidenceVerificationStatus.pending,
      hashVerifiedAtUtc: null,
      uploadedBy: uploadedBy,
      attachedAtUtc: attachedAtUtc,
      deletedAtUtc: null,
    );
  }

  @override
  Future<List<DisputeEvidenceAttachment>> findByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  }) async => const [];

  @override
  Future<int> countActiveByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  }) async => 0;

  @override
  Future<void> softDelete({
    required String organizationId,
    required String attachmentId,
    required DateTime deletedAtUtc,
  }) async {
    softDeleteCalls++;
    lastDeletedId = attachmentId;
  }
}

ProviderContainer _container(
  _CapturingRepo repo, {
  String? orgId = 'org-1',
  String? operatorId = 'user-1',
}) {
  final c = ProviderContainer(
    overrides: [
      disputeEvidenceRepositoryProvider.overrideWithValue(repo),
      currentOrganizationIdProvider.overrideWithValue(orgId),
      currentOperatorIdProvider.overrideWithValue(operatorId),
      dateTimeProviderProvider.overrideWithValue(
        _FixedClock(DateTime.utc(2026, 1, 15, 12, 0)),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('upload seals bytes with SHA-256 client-side (INV-9)', () async {
    final repo = _CapturingRepo();
    final c = _container(repo);
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final expected = sha256.convert(bytes).toString();

    final controller = c.read(
      disputeEvidenceControllerProvider(_qid).notifier,
    );
    final ok = await controller.upload(
      fileName: 'laudo.png',
      mimeType: 'image/png',
      bytes: bytes,
    );

    expect(ok, isTrue);
    expect(repo.lastHash, expected);
    expect(repo.lastFileName, 'laudo.png');
    expect(repo.lastMime, 'image/png');
    expect(c.read(disputeEvidenceControllerProvider(_qid)).hasError, isFalse);
  });

  test('upload without org fails fast with error state', () async {
    final repo = _CapturingRepo();
    final c = _container(repo, orgId: null);

    final controller = c.read(
      disputeEvidenceControllerProvider(_qid).notifier,
    );
    final ok = await controller.upload(
      fileName: 'x.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([9]),
    );

    expect(ok, isFalse);
    expect(repo.lastHash, isNull);
    expect(c.read(disputeEvidenceControllerProvider(_qid)).hasError, isTrue);
  });

  test('rejectFile surfaces a domain-language error', () {
    final repo = _CapturingRepo();
    final c = _container(repo);

    c
        .read(disputeEvidenceControllerProvider(_qid).notifier)
        .rejectFile('Tipo de arquivo não permitido.');

    final state = c.read(disputeEvidenceControllerProvider(_qid));
    expect(state.hasError, isTrue);
    expect(state.error, 'Tipo de arquivo não permitido.');
  });

  test('remove soft-deletes via the repository (INV-3)', () async {
    final repo = _CapturingRepo();
    final c = _container(repo);

    final ok = await c
        .read(disputeEvidenceControllerProvider(_qid).notifier)
        .remove('att-9');

    expect(ok, isTrue);
    expect(repo.softDeleteCalls, 1);
    expect(repo.lastDeletedId, 'att-9');
  });
}
