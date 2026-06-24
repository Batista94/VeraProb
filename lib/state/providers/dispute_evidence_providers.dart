import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'admin_providers.dart';
import 'auth_providers.dart';
import 'shared_providers.dart';

/// Componente 5.2 — Whether the current org's plan includes paid dispute-
/// evidence storage. Derived from the tenant-readable org settings; the upload
/// panel gates on this so an org without a contracted storage plan sees a clear
/// message instead of a silent failure. Loading/error propagate so the panel
/// can fail closed (no upload surface until storage is confirmed enabled).
final evidenceStorageEnabledProvider = Provider.autoDispose<AsyncValue<bool>>((
  ref,
) {
  return ref
      .watch(orgSettingsProvider)
      .whenData((org) => org?.evidenceStorageEnabled ?? false);
});

/// Active (non-soft-deleted) evidence attachments for a disputed sanction
/// (Componente 4.3). Keyed by `queueEntryId`. RLS scopes the read to the org.
final disputeEvidenceListProvider = FutureProvider.autoDispose
    .family<List<DisputeEvidenceAttachment>, String>((ref, queueEntryId) async {
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return const <DisputeEvidenceAttachment>[];
      final repo = ref.watch(disputeEvidenceRepositoryProvider);
      return repo.findByQueueEntryId(
        organizationId: orgId,
        queueEntryId: queueEntryId,
      );
    });

/// Per-dispute upload/delete controller. Hosts the orchestration the feature
/// widget must NOT do itself (INV-13: features never touch the repository or
/// the domain SHA-256 seal). [AsyncValue] tracks the in-flight upload so the
/// panel can show a [LinearProgressIndicator] + domain-language errors.
final disputeEvidenceControllerProvider = NotifierProvider.autoDispose
    .family<DisputeEvidenceController, AsyncValue<void>, String>(
      DisputeEvidenceController.new,
    );

class DisputeEvidenceController extends Notifier<AsyncValue<void>> {
  DisputeEvidenceController(this.queueEntryId);
  final String queueEntryId;

  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Surfaces a client-side pre-validation failure (wrong MIME, too large,
  /// empty) as the controller's error state so the panel renders it uniformly
  /// with upload failures. The boundary widget cannot set [state] directly.
  void rejectFile(String message) =>
      state = AsyncError(message, StackTrace.current);

  /// Seals [bytes] with SHA-256 client-side (INV-9), then attaches via the repo.
  /// Returns true on success. On failure, [state] carries a domain-language
  /// message and the method returns false (Lesson #5 — no raw errors).
  Future<bool> upload({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final orgId = ref.read(currentOrganizationIdProvider);
    final uploadedBy = ref.read(currentOperatorIdProvider);
    if (orgId == null || uploadedBy == null) {
      state = AsyncError(
        'Sessão inválida. Faça login novamente.',
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncLoading();
    try {
      final sha256Hash = sha256.convert(bytes).toString();
      final clock = ref.read(dateTimeProviderProvider);
      await ref
          .read(disputeEvidenceRepositoryProvider)
          .attach(
            organizationId: orgId,
            queueEntryId: queueEntryId,
            fileName: fileName,
            mimeType: mimeType,
            sha256Hash: sha256Hash,
            uploadedBy: uploadedBy,
            fileBytes: bytes,
            attachedAtUtc: clock.nowUtc(),
          );
      ref.invalidate(disputeEvidenceListProvider(queueEntryId));
      state = const AsyncData(null);
      return true;
    } on DomainException catch (e) {
      state = AsyncError(e.message, StackTrace.current);
      return false;
    } catch (_) {
      state = AsyncError(
        'Não foi possível anexar a evidência. Tente novamente.',
        StackTrace.current,
      );
      return false;
    }
  }

  /// Soft-deletes an attachment (INV-3 — never hard-deletes). Returns true on
  /// success; on failure [state] holds a domain-language message.
  Future<bool> remove(String attachmentId) async {
    final orgId = ref.read(currentOrganizationIdProvider);
    if (orgId == null) {
      state = AsyncError(
        'Sessão inválida. Faça login novamente.',
        StackTrace.current,
      );
      return false;
    }
    try {
      final clock = ref.read(dateTimeProviderProvider);
      await ref
          .read(disputeEvidenceRepositoryProvider)
          .softDelete(
            organizationId: orgId,
            attachmentId: attachmentId,
            deletedAtUtc: clock.nowUtc(),
          );
      ref.invalidate(disputeEvidenceListProvider(queueEntryId));
      return true;
    } on DomainException catch (e) {
      state = AsyncError(e.message, StackTrace.current);
      return false;
    } catch (_) {
      state = AsyncError(
        'Não foi possível remover a evidência. Tente novamente.',
        StackTrace.current,
      );
      return false;
    }
  }
}
