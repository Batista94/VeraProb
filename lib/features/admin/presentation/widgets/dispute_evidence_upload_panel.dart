import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart'; // pr_scanner: ignore
import 'package:veraprob/state/providers/dispute_evidence_providers.dart';

/// Componente 4.3 — Cryptographic evidence upload for a disputed sanction.
///
/// Client-side SHA-256 seal (INV-9) happens in [DisputeEvidenceController];
/// this panel is the boundary: it picks a file, pre-validates MIME + size
/// (fast, domain-language feedback — Lesson #5), shows upload progress, lists
/// the sealed attachments as dismissible chips (file name + human size, NEVER
/// the UUID), and surfaces each row's server re-verification badge
/// (PENDENTE / VERIFICADO / DIVERGENTE).
class DisputeEvidenceUploadPanel extends ConsumerWidget {
  final String queueEntryId;

  const DisputeEvidenceUploadPanel({super.key, required this.queueEntryId});

  /// Mirrors `DisputeEvidenceRepository.maxAttachmentsPerDispute` (the port is
  /// domain; features must not import it — INV-13).
  static const int _kMaxAttachments = 10;

  static const int _kMaxBytes = 10 * 1024 * 1024; // 10 MB

  /// Extension → MIME, mirroring the domain allow-list (`validated`).
  static const Map<String, String> _allowedExtensions = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'pdf': 'application/pdf',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'webp': 'image/webp',
  };

  Future<void> _pickAndUpload(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions.keys.toList(),
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = _allowedExtensions[ext];
    final controller = ref.read(
      disputeEvidenceControllerProvider(queueEntryId).notifier,
    );

    if (mime == null) {
      controller.rejectFile(
        'Tipo de arquivo não permitido. Use JPG, PNG, PDF, HEIC ou WEBP.',
      );
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      controller.rejectFile('Arquivo vazio ou ilegível.');
      return;
    }
    if (bytes.length > _kMaxBytes) {
      controller.rejectFile('Arquivo excede o limite de 10 MB.');
      return;
    }

    await controller.upload(fileName: file.name, mimeType: mime, bytes: bytes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 5.2 storage-plan gate: an org without contracted evidence storage sees a
    // clear message, never a silent upload failure. Fail closed on load/error.
    final storageAsync = ref.watch(evidenceStorageEnabledProvider);
    return switch (storageAsync) {
      AsyncData(:final value) when value => _buildEnabled(context, ref),
      AsyncData() => const _StorageGate(
        icon: Icons.lock_outline,
        message:
            'Armazenamento de evidências não está habilitado no plano desta '
            'organização. Fale com o suporte para ativar.',
      ),
      AsyncLoading() => const _StorageGate.loading(),
      AsyncError() => const _StorageGate(
        icon: Icons.cloud_off_outlined,
        message:
            'Não foi possível verificar o plano de armazenamento. Tente '
            'novamente mais tarde.',
      ),
    };
  }

  Widget _buildEnabled(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(disputeEvidenceListProvider(queueEntryId));
    final uploadState = ref.watch(
      disputeEvidenceControllerProvider(queueEntryId),
    );

    final count = switch (listAsync) {
      AsyncData(:final value) => value.length,
      _ => 0,
    };
    final atLimit = count >= _kMaxAttachments;
    final isUploading = uploadState.isLoading;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.attach_file_outlined,
                size: 16,
                color: VeraProbColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Evidências',
                style: VeraProbTypography.sectionTitle.copyWith(fontSize: 14),
              ),
              const Spacer(),
              Text(
                '$count/$_kMaxAttachments',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: atLimit
                      ? VeraProbColors.warning
                      : VeraProbColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (isUploading) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 6),
            const Text(
              'Selando e enviando…',
              style: TextStyle(
                fontSize: 11,
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
          ],

          OutlinedButton.icon(
            key: const ValueKey('dispute-evidence-add-button'),
            onPressed: (atLimit || isUploading)
                ? null
                : () => _pickAndUpload(ref),
            icon: const Icon(Icons.upload_file_outlined, size: 16),
            label: Text(
              atLimit ? 'Limite de 10 anexos atingido' : 'Anexar evidência',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: VeraProbColors.primary,
              side: BorderSide(
                color: VeraProbColors.primary.withValues(alpha: 0.5),
              ),
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),

          if (uploadState case AsyncError()) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 14,
                  color: VeraProbColors.error,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Falha ao processar evidência. Tente novamente.',
                    style: TextStyle(fontSize: 11, color: VeraProbColors.error),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),
          switch (listAsync) {
            AsyncLoading() => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            AsyncError() => const Text(
              'Não foi possível carregar as evidências.',
              style: TextStyle(fontSize: 11, color: VeraProbColors.error),
            ),
            AsyncData(:final value) =>
              value.isEmpty
                  ? const Text(
                      'Nenhuma evidência anexada.',
                      style: TextStyle(
                        fontSize: 11,
                        color: VeraProbColors.textDisabled,
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in value)
                          _EvidenceChip(
                            attachment: a,
                            onRemove: () => _confirmRemove(context, ref, a),
                          ),
                      ],
                    ),
          },
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    DisputeEvidenceAttachment a,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VeraProbColors.surface,
        title: const Text('Remover evidência?'),
        content: Text(
          'Remover "${a.fileName}" da disputa? O registro permanece selado no '
          'ledger forense.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: VeraProbColors.error),
            child: const Text('REMOVER'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(disputeEvidenceControllerProvider(queueEntryId).notifier)
        .remove(a.id);
  }
}

/// 5.2 plan gate / status shell shown in place of the uploader when evidence
/// storage is not confirmed enabled (disabled plan, still loading, or unknown).
class _StorageGate extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool loading;

  const _StorageGate({required this.icon, required this.message})
    : loading = false;

  const _StorageGate.loading()
    : icon = Icons.hourglass_empty_outlined,
      message = '',
      loading = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('evidence-storage-gate'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 18, color: VeraProbColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              loading ? 'Verificando plano de armazenamento…' : message,
              style: const TextStyle(
                fontSize: 12,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  final DisputeEvidenceAttachment attachment;
  final VoidCallback onRemove;

  const _EvidenceChip({required this.attachment, required this.onRemove});

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.xlAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _VerificationBadge(status: attachment.verificationStatus),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: VeraProbColors.textPrimary,
                  ),
                ),
                Text(
                  _formatSize(attachment.fileSizeBytes),
                  style: const TextStyle(
                    fontSize: 10,
                    color: VeraProbColors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            key: ValueKey('evidence-remove-${attachment.id}'),
            borderRadius: VeraProbRadii.lgAll,
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 14,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  final EvidenceVerificationStatus status;

  const _VerificationBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      EvidenceVerificationStatus.verified => (
        VeraProbColors.onTime,
        Icons.verified_outlined,
        'VERIFICADO',
      ),
      EvidenceVerificationStatus.mismatch => (
        VeraProbColors.error,
        Icons.gpp_bad_outlined,
        'DIVERGENTE',
      ),
      EvidenceVerificationStatus.pending => (
        VeraProbColors.warning,
        Icons.hourglass_empty_outlined,
        'PENDENTE',
      ),
    };

    return Tooltip(
      message: 'Verificação de hash: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: VeraProbRadii.lgAll,
        ),
        child: Icon(icon, size: 12, color: color),
      ),
    );
  }
}
