import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/features/admin/presentation/widgets/csv_importer/_csv_theme.dart';
import 'package:veraprob/features/admin/providers/csv_import_providers.dart';

/// Step 2 — preflight validation report: summary + error table + import CTA.
class CsvValidationStep extends ConsumerWidget {
  const CsvValidationStep({super.key, required this.isSubmitting});

  final bool isSubmitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(csvImportFlowProvider);
    if (state is! CsvImportValidated) return const SizedBox.shrink();

    final report = state.report;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCard(
            totalRows: report.totalRows,
            validRows: report.validRows,
            errorCount: report.errors.length,
          ),
          if (report.hasErrors) ...[
            const SizedBox(height: 12),
            _WarningBanner(errorCount: report.errors.length),
            const SizedBox(height: 12),
            _ErrorTable(errors: report.errors),
          ] else ...[
            const SizedBox(height: 12),
            _CleanBanner(validRows: report.validRows),
          ],
        ],
      ),
    );
  }
}

// ── Summary Card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalRows,
    required this.validRows,
    required this.errorCount,
  });

  final int totalRows;
  final int validRows;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    final pct = totalRows > 0 ? validRows / totalRows : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: CsvT.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Total de linhas',
                  value: '$totalRows',
                  color: CsvT.textHi,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Linhas válidas',
                  value: '$validRows',
                  color: CsvT.success,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Erros',
                  value: '$errorCount',
                  color: errorCount > 0 ? CsvT.warning : CsvT.textLo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: CsvT.bgSlate,
              valueColor: AlwaysStoppedAnimation(
                errorCount > 0 ? CsvT.warning : CsvT.success,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% prontas para importar',
            style: CsvT.labelStyle(color: CsvT.textLo, size: 12),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: CsvT.labelStyle(color: CsvT.textLo, size: 11)),
      ],
    );
  }
}

// ── Banners ───────────────────────────────────────────────────────────────────

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.errorCount});

  final int errorCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CsvT.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CsvT.radiusChip),
        border: Border.all(color: CsvT.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: CsvT.warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$errorCount linha(s) com erros serão ignoradas. '
              'As demais serão importadas normalmente (importação parcial).',
              style: CsvT.labelStyle(color: CsvT.warning, size: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CleanBanner extends StatelessWidget {
  const _CleanBanner({required this.validRows});

  final int validRows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CsvT.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CsvT.radiusChip),
        border: Border.all(color: CsvT.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: CsvT.success, size: 18),
          const SizedBox(width: 8),
          Text(
            'Arquivo sem erros — $validRows linha(s) prontas para importar.',
            style: CsvT.labelStyle(color: CsvT.success, size: 12),
          ),
        ],
      ),
    );
  }
}

// ── Error Table ───────────────────────────────────────────────────────────────

class _ErrorTable extends StatelessWidget {
  const _ErrorTable({required this.errors});

  final List<CsvRowError> errors;

  static const _kMaxDisplay = 50;

  @override
  Widget build(BuildContext context) {
    final display = errors.take(_kMaxDisplay).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detalhes dos erros${errors.length > _kMaxDisplay ? ' (exibindo $_kMaxDisplay de ${errors.length})' : ''}',
          style: CsvT.labelStyle(color: CsvT.textLo, size: 12),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: CsvT.cardDecoration(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(CsvT.bgSlate),
              dataRowColor: WidgetStateProperty.all(CsvT.bgCard),
              headingTextStyle: CsvT.labelStyle(color: CsvT.textLo, size: 11),
              dataTextStyle: CsvT.labelStyle(color: CsvT.textHi, size: 12),
              columnSpacing: 16,
              horizontalMargin: 12,
              columns: const [
                DataColumn(label: Text('Linha')),
                DataColumn(label: Text('Coluna CSV')),
                DataColumn(label: Text('Código')),
                DataColumn(label: Text('Mensagem')),
              ],
              rows: display.map((e) {
                return DataRow(
                  cells: [
                    DataCell(Text('${e.rowIndex}')),
                    DataCell(
                      Text(e.csvHeader, overflow: TextOverflow.ellipsis),
                    ),
                    DataCell(
                      Text(
                        e.errorCode,
                        style: CsvT.labelStyle(color: CsvT.warning, size: 11),
                      ),
                    ),
                    DataCell(
                      Tooltip(
                        message: e.message,
                        preferBelow: false,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Text(
                            e.message,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            softWrap: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
