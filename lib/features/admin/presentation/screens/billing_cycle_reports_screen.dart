import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../features/shared/providers/reporting_providers.dart';
import '../../../../domain/sla_audit/billing_cycle_report.dart';
import '../../../../state/providers/contract_providers.dart';
import '../../../../state/providers/auth_providers.dart';

class BillingCycleReportsScreen extends ConsumerStatefulWidget {
  const BillingCycleReportsScreen({super.key});

  @override
  ConsumerState<BillingCycleReportsScreen> createState() =>
      _BillingCycleReportsScreenState();
}

class _BillingCycleReportsScreenState
    extends ConsumerState<BillingCycleReportsScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String? _selectedContractId;
  bool _isLoading = false;
  BillingCycleReport? _report;

  Future<void> _generateReport() async {
    final organizationId = ref.read(currentOrganizationIdProvider);
    if (organizationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
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
      setState(() => _report = report);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_report == null) return;
    try {
      final csv = ref.read(exportServiceProvider).generateCsv(_report!);
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv')); // UTF-8 BOM
      await FileSaver.instance.saveFile(
        name:
            'relatorio_auditoria_${DateTime.now().millisecondsSinceEpoch}',
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relatório CSV baixado com sucesso!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao exportar CSV: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportPdf() async {
    if (_report == null) return;
    try {
      final pdfList = await ref
          .read(exportServiceProvider)
          .generatePdf(_report!);
      final pdfBytes = Uint8List.fromList(pdfList);
      await FileSaver.instance.saveFile(
        name:
            'relatorio_auditoria_${DateTime.now().millisecondsSinceEpoch}',
        bytes: pdfBytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relatório PDF gerado com sucesso!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao exportar PDF: $e'),
          backgroundColor: Colors.red,
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
        Row(
          children: [
            contractsAsync.when(
              loading: () =>
                  const SizedBox(width: 220, child: LinearProgressIndicator()),
              error: (_, _) => const Text('Erro ao carregar contratos'),
              data: (contracts) => DropdownButton<String?>(
                value: _selectedContractId,
                hint: const Text('Todos os contratos'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos os contratos'),
                  ),
                  ...contracts.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text('${c.name} — ${c.contractorName}'),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedContractId = value),
              ),
            ),
            const SizedBox(width: 16),
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
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _generateReport,
              child: const Text('Gerar Relatório'),
            ),
            if (_report != null) ...[
              const SizedBox(width: 16),
              IconButton(
                onPressed: _exportCsv,
                icon: const Icon(Icons.table_view_rounded),
                tooltip: 'Exportar CSV',
                color: Colors.green.shade700,
              ),
              IconButton(
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded),
                tooltip: 'Exportar PDF',
                color: Colors.red.shade700,
              ),
            ],
          ],
        ),
        if (_selectedContractId == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange),
                SizedBox(width: 4),
                Text(
                  'Nenhum contrato selecionado — relatório agrega todos os contratos.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
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
                trailing: Text(_formatCents(s.totalContractedRevenue.cents)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(BillingCycleReport report) {
    return Row(
      children: [
        _buildCard(
          'Faturamento',
          _formatCents(report.totalContractedRevenue.cents),
        ),
        _buildCard('Protegido', _formatCents(report.protectedRevenue.cents)),
        _buildCard(
          'Perda',
          _formatCents(report.lostRevenue.cents),
          color: Colors.red,
        ),
        _buildCard(
          'Risco',
          _formatCents(report.revenueAtRisk.cents),
          color: Colors.orange,
        ),
      ],
    );
  }

  Widget _buildCard(String label, String value, {Color? color}) {
    return Expanded(
      child: Card(
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
      ),
    );
  }

  Widget _buildWarning(BillingCycleReport report) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Relatório Incompleto: Faltam ${report.missingDates.length} dias operacionais.',
              style: const TextStyle(color: Colors.red),
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
