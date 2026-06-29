import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/shared/providers/reporting_providers.dart';
import 'package:veraprob/application/shared/billing_cycle_view.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

class BillingCycleReportsScreen extends ConsumerStatefulWidget {
  const BillingCycleReportsScreen({super.key});

  @override
  ConsumerState<BillingCycleReportsScreen> createState() =>
      _BillingCycleReportsScreenState();
}

class _BillingCycleReportsScreenState
    extends ConsumerState<BillingCycleReportsScreen> {
  DateTime _startDate = DateTime.now().toUtc().subtract(
    const Duration(days: 30),
  );
  DateTime _endDate = DateTime.now().toUtc();
  String? _selectedContractId;
  bool _isLoading = false;
  BillingCycleView? _report;

  Future<void> _generateReport() async {
    final messenger = ScaffoldMessenger.of(context);
    final organizationId = ref.read(currentOrganizationIdProvider);
    if (organizationId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sessão inválida. Faça login novamente.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final report = await ref
          .read(reportingServiceProvider)
          .generateBillingCycleReport(
            organizationId: organizationId,
            periodStartUtc: _startDate,
            periodEndUtc: _endDate,
            contractId: _selectedContractId,
          );
      if (mounted) {
        setState(() => _report = BillingCycleView.fromDomain(report));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _exportCsv() async {
    if (_report == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = ref.read(exportServiceProvider).generateCsv(_report!);
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv')); // UTF-8 BOM
      await FileSaver.instance.saveFile(
        name:
            'relatorio_auditoria_${DateTime.now().toUtc().millisecondsSinceEpoch}',
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Relatório CSV baixado com sucesso!')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível exportar o arquivo CSV. Tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }

  Future<void> _exportPdf() async {
    if (_report == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pdfList = await ref
          .read(exportServiceProvider)
          .generatePdf(_report!);
      final pdfBytes = Uint8List.fromList(pdfList);
      await FileSaver.instance.saveFile(
        name:
            'relatorio_auditoria_${DateTime.now().toUtc().millisecondsSinceEpoch}',
        bytes: pdfBytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Relatório PDF gerado com sucesso!')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível exportar o arquivo PDF. Tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios de Ciclo de Faturamento')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilters(),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_report != null)
              Expanded(child: _buildReportView())
            else
              const Center(
                child: Text('Selecione o período e gere o relatório.'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final df = DateFormat('dd/MM/yyyy');
    final contractsAsync = ref.watch(contractListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            switch (contractsAsync) {
              AsyncData(:final value) => SizedBox(
                width: 260,
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _selectedContractId,
                  hint: const Text('Todos os contratos'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos os contratos'),
                    ),
                    ...value.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(
                          '${c.name} — ${c.contractorName}',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedContractId = value),
                ),
              ),
              AsyncLoading() => const SizedBox(
                width: 220,
                child: LinearProgressIndicator(),
              ),
              AsyncError() => const Text('Erro ao carregar contratos'),
            },
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2027),
                  initialDateRange: DateTimeRange(
                    start: _startDate,
                    end: _endDate,
                  ),
                );
                if (picked != null) {
                  setState(() {
                    _startDate = picked.start;
                    _endDate = picked.end;
                  });
                }
              },
              icon: const Icon(Icons.date_range),
              label: Text('${df.format(_startDate)} - ${df.format(_endDate)}'),
            ),
            ElevatedButton(
              onPressed: _generateReport,
              child: const Text('Gerar Relatório'),
            ),
            if (_report != null) ...[
              IconButton(
                onPressed: _exportCsv,
                icon: const Icon(Icons.table_view_rounded),
                tooltip: 'Exportar CSV',
                color: VeraProbColors.success,
              ),
              IconButton(
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded),
                tooltip: 'Exportar PDF',
                color: VeraProbColors.error,
              ),
            ],
          ],
        ),
        if (_selectedContractId == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: VeraProbColors.warning,
                ),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Nenhum contrato selecionado — relatório agrega todos os contratos.',
                    style: TextStyle(
                      fontSize: 12,
                      color: VeraProbColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildReportView() {
    final report = _report!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCards(report),
        const SizedBox(height: 20),
        if (!report.isComplete) _buildWarning(report),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            itemCount: report.snapshots.length,
            itemBuilder: (context, index) {
              final s = report.snapshots[index];
              return ListTile(
                title: Text(
                  DateFormat('dd/MM/yyyy').format(s.operationalDateUtc),
                ),
                subtitle: Text(
                  'Executadas: ${s.executedCount} / ${s.totalObligations}',
                ),
                trailing: Text(_formatCents(s.totalContractedRevenue)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(BillingCycleView report) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _buildCard(
            'Faturamento',
            _formatCents(report.totalContractedRevenue),
          ),
          _buildCard('Protegido', _formatCents(report.protectedRevenue)),
          _buildCard(
            'Perda',
            _formatCents(report.lostRevenue),
            color: VeraProbColors.error,
          ),
          _buildCard(
            'Risco',
            _formatCents(report.revenueAtRisk),
            color: VeraProbColors.warning,
          ),
        ];

        if (constraints.maxWidth < 600) {
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.0,
            children: cards,
          );
        } else {
          return Row(children: cards.map((c) => Expanded(child: c)).toList());
        }
      },
    );
  }

  Widget _buildCard(String label, String value, {Color? color}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarning(BillingCycleView report) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.error),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: VeraProbColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Relatório Incompleto: Faltam ${report.missingDates.length} dias operacionais.',
              style: const TextStyle(color: VeraProbColors.error),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCents(int cents) {
    return NumberFormat.simpleCurrency(locale: 'pt_BR').format(cents / 100);
  }
}
