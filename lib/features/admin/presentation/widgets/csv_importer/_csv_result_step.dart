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
    final success = result.rowsImported > 0 || !hasErrors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResultCard(
            success: success,
            rowsImported: result.rowsImported,
            rowsSkipped: result.rowsSkipped,
            totalProcessed: result.totalProcessed,
          ),
          if (hasErrors) ...[
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
    required this.rowsImported,
    required this.rowsSkipped,
    required this.totalProcessed,
  });

  final bool success;
  final int rowsImported;
  final int rowsSkipped;
  final int totalProcessed;

  @override
  Widget build(BuildContext context) {
    final color = success ? CsvT.success : CsvT.error;
    final icon = success ? Icons.check_circle_outline : Icons.error_outline;
    final title = success
        ? '$rowsImported registro(s) importado(s) com sucesso'
        : 'Falha na importação';

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
          if (success && rowsSkipped > 0) ...[
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
        'Baixar ${errors.length} erro(s) em CSV',
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
