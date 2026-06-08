import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/features/admin/presentation/utils/csv_error_exporter.dart';
import 'package:veraprob/features/admin/presentation/widgets/csv_importer/_csv_theme.dart';
import 'package:veraprob/features/admin/providers/csv_import_providers.dart';

/// Step 3 — import result: success/failure card + download error CSV + close.
class CsvResultStep extends ConsumerWidget {
  const CsvResultStep({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(csvImportFlowProvider);
    if (state is! CsvImportDone) return const SizedBox.shrink();

    final result = state.result;
    final hasErrors = result.hasErrors;
    final isPartial = result.rowsImported > 0 && hasErrors;
    final success = result.rowsImported > 0 || !hasErrors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResultCard(
            success: success,
            isPartial: isPartial,
            rowsImported: result.rowsImported,
            rowsSkipped: result.rowsSkipped,
            totalProcessed: result.totalProcessed,
          ),
          if (hasErrors) ...[
            const SizedBox(height: 16),
            _InlineErrorList(errors: result.errors),
            const SizedBox(height: 16),
            _DownloadErrorsButton(errors: result.errors),
          ],
          if (result.savedTemplateId != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: CsvT.action.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(CsvT.radiusChip),
                border: Border.all(color: CsvT.action.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bookmark_added_outlined,
                    color: CsvT.action,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Template salvo com sucesso para reutilização futura.',
                      style: CsvT.labelStyle(color: CsvT.action, size: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onClose,
              style: FilledButton.styleFrom(
                backgroundColor: CsvT.action,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CsvT.radiusChip),
                ),
              ),
              child: const Text('Concluir'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result Card ───────────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.success,
    required this.isPartial,
    required this.rowsImported,
    required this.rowsSkipped,
    required this.totalProcessed,
  });

  final bool success;
  final bool isPartial;
  final int rowsImported;
  final int rowsSkipped;
  final int totalProcessed;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String title;

    if (isPartial) {
      color = CsvT.warning;
      icon = Icons.warning_amber_rounded;
      title = '$rowsImported importado(s), $rowsSkipped ignorado(s) por erro';
    } else if (success) {
      color = CsvT.success;
      icon = Icons.check_circle_outline;
      title = '$rowsImported registro(s) importado(s) com sucesso';
    } else {
      color = CsvT.error;
      icon = Icons.error_outline;
      title = 'Falha na importação';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CsvT.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 48),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (success && !isPartial && rowsSkipped > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$rowsSkipped linha(s) ignorada(s) por erros de validação.',
              style: CsvT.labelStyle(color: CsvT.textLo, size: 12),
              textAlign: TextAlign.center,
            ),
          ],
          if (success) ...[
            const SizedBox(height: 8),
            Text(
              'Total processado: $totalProcessed linha(s).',
              style: CsvT.labelStyle(color: CsvT.textLo, size: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Inline Error List ─────────────────────────────────────────────────────────

class _InlineErrorList extends StatelessWidget {
  const _InlineErrorList({required this.errors});

  final List<CsvRowError> errors;

  static const _kMaxInline = 5;

  @override
  Widget build(BuildContext context) {
    final preview = errors.take(_kMaxInline).toList();
    final overflow = errors.length - _kMaxInline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...preview.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'L${e.rowIndex}',
                  style: CsvT.labelStyle(color: CsvT.warning, size: 11),
                ),
                const SizedBox(width: 8),
                Text(
                  e.csvHeader,
                  style: CsvT.labelStyle(color: CsvT.textLo, size: 11),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.message,
                    style: CsvT.labelStyle(color: CsvT.textHi, size: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (overflow > 0) ...[
          const SizedBox(height: 4),
          Text(
            '... e mais $overflow erro(s)',
            style: CsvT.labelStyle(color: CsvT.textLo, size: 11),
          ),
        ],
      ],
    );
  }
}

// ── Download Errors Button ────────────────────────────────────────────────────

class _DownloadErrorsButton extends StatelessWidget {
  const _DownloadErrorsButton({required this.errors});

  final List<CsvRowError> errors;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => CsvErrorExporter.download(
        errors,
        'erros_importacao_${DateTime.now().toUtc().millisecondsSinceEpoch}',
      ),
      icon: const Icon(Icons.download_outlined, size: 16, color: CsvT.warning),
      label: Text(
        'Exportar todos os ${errors.length} erro(s) em CSV',
        style: CsvT.labelStyle(color: CsvT.warning),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: CsvT.warning),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CsvT.radiusChip),
        ),
      ),
    );
  }
}
