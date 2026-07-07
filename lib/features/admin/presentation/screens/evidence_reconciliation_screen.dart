import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_category_chip.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_link_source_chip.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/telegram_providers.dart';

/// WS-4 Evidence Reconciliation Screen — auditor triage for orphan evidence.
///
/// Displays orphan evidence uploads (requires_manual_link=true, no reconciliation link)
/// and allows AUDITOR/TENANT_ADMIN to manually link them to execution sets.
///
/// RBAC: Access controlled at navigation level (AdminDestination.minimumRole).
/// INV-1: All data org-scoped via orphanEvidencesProvider.
/// INV-7: Linking is append-only (INSERT into telegram_evidence_links).
class EvidenceReconciliationScreen extends ConsumerWidget {
  const EvidenceReconciliationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orphansAsync = ref.watch(orphanEvidencesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(orphansAsync: orphansAsync),
            const SizedBox(height: 24),
            Expanded(
              child: AsyncValueWidget(
                asyncValue: orphansAsync,
                loading: () => const SkeletonListLoader(),
                data: (value) => value.isEmpty
                    ? const EmptyState(
                        icon: Icons.check_circle_outline,
                        iconColor: VeraProbColors.success,
                        title: 'Nenhuma evidência órfã',
                        description:
                            'Todas as evidências foram vinculadas a execuções.',
                      )
                    : ListView.separated(
                        itemCount: value.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            _OrphanEvidenceCard(evidence: value[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AsyncValue<List<TelegramEvidenceUpload>> orphansAsync;

  const _Header({required this.orphansAsync});

  @override
  Widget build(BuildContext context) {
    final count = switch (orphansAsync) {
      AsyncData(:final value) => value.length,
      AsyncError() => 0,
      AsyncLoading() => 0,
    };
    return VeraProbHeader(
      icon: Icons.link_off_rounded,
      iconColor: VeraProbColors.warning,
      title: 'Reconciliação de Evidências',
      actions: [
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: VeraProbColors.warning.withValues(alpha: 0.12),
              borderRadius: VeraProbRadii.lgAll,
            ),
            child: Text(
              '$count órfã${count > 1 ? 's' : ''}',
              style: VeraProbTypography.badge.copyWith(
                color: VeraProbColors.warning,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Orphan Evidence Card ──────────────────────────────────────────────────────

class _OrphanEvidenceCard extends ConsumerWidget {
  final TelegramEvidenceUpload evidence;

  const _OrphanEvidenceCard({required this.evidence});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
    final ext = evidence.fileName.split('.').last.toUpperCase();

    return PanelContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: file type badge + hash + timestamp
          Row(
            children: [
              _TypeBadge(ext: ext),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '🔐 ${evidence.forensicHash.substring(0, 16)}…',
                      style: VeraProbTypography.mono(
                        size: 12,
                        color: VeraProbColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Captura: ${dateFmt.format(evidence.telegramMessageDate.toLocal())}',
                      style: VeraProbTypography.caption,
                    ),
                  ],
                ),
              ),
              // Vincular button
              FilledButton.icon(
                onPressed: () => _showLinkDialog(context, ref),
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('Vincular'),
                style: FilledButton.styleFrom(
                  backgroundColor: VeraProbColors.primary,
                  foregroundColor: VeraProbColors.background,
                  textStyle: VeraProbTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Bottom row: metadata
          Row(
            children: [
              EvidenceCategoryChip(category: evidence.category),
              if (evidence.linkSource != null) ...[
                const SizedBox(width: 6),
                EvidenceLinkSourceChip(source: evidence.linkSource!),
              ],
              const SizedBox(width: 12),
              _MetaChip(
                icon: Icons.person_outline,
                label: 'Driver: ${evidence.driverId.substring(0, 8)}…',
              ),
              const SizedBox(width: 12),
              _MetaChip(
                icon: Icons.chat_outlined,
                label: 'Chat: ${evidence.chatId}',
              ),
              const SizedBox(width: 12),
              _MetaChip(
                icon: Icons.schedule_outlined,
                label:
                    'Upload: ${dateFmt.format(evidence.uploadedAtUtc.toLocal())}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLinkDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VeraProbColors.surface,
        title: Text(
          'Vincular Evidência',
          style: VeraProbTypography.sectionTitle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hash: ${evidence.forensicHash.substring(0, 16)}…',
              style: VeraProbTypography.caption,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: VeraProbTypography.bodyMedium,
              decoration: InputDecoration(
                labelText: 'ID da Execução (set_id)',
                labelStyle: VeraProbTypography.fieldLabel,
                hintText: 'Ex: exec_abc123',
                hintStyle: VeraProbTypography.caption,
                border: const OutlineInputBorder(),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: VeraProbColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: VeraProbColors.primary),
                ),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: VeraProbColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              final setId = controller.text.trim();
              if (setId.isEmpty) return;
              ref
                  .read(linkEvidenceNotifierProvider.notifier)
                  .link(evidenceUploadId: evidence.id, executionSetId: setId);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.primary,
              foregroundColor: VeraProbColors.background,
            ),
            child: const Text('Confirmar Vínculo'),
          ),
        ],
      ),
    );
  }
}

// ── Reusable Widgets ──────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String ext;

  const _TypeBadge({required this.ext});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (ext) {
      'JPG' ||
      'JPEG' ||
      'PNG' ||
      'WEBP' ||
      'HEIC' => (VeraProbColors.info, Icons.image_outlined),
      'PDF' => (VeraProbColors.warning, Icons.picture_as_pdf_outlined),
      'MP4' => (VeraProbColors.secondary, Icons.videocam_outlined),
      'OGG' => (VeraProbColors.secondary, Icons.mic_rounded),
      _ => (VeraProbColors.neutral, Icons.insert_drive_file_outlined),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: VeraProbRadii.mdAll,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: VeraProbColors.textDisabled),
        const SizedBox(width: 4),
        Text(label, style: VeraProbTypography.caption),
      ],
    );
  }
}
