import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:pactaflow/application/sla_audit/projections/contract_detail_view.dart';
import 'package:pactaflow/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:pactaflow/domain/sla_audit/contract_status.dart';
import 'package:pactaflow/domain/sla_audit/execution_status.dart';
import 'package:pactaflow/domain/shared/money.dart';
import 'package:pactaflow/state/providers/contract_providers.dart';

import 'declare_contract_plan_form.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');
final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
final _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

class ContractDetailScreen extends ConsumerWidget {
  final String contractId;

  const ContractDetailScreen({super.key, required this.contractId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(contractDetailProvider(contractId));

    return detailAsync.when(
      data: (detail) {
        if (detail == null) {
          return const Center(child: Text('Contrato não encontrado.'));
        }
        return _DetailView(detail: detail);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Erro ao carregar contrato: $e',
            style: const TextStyle(color: Colors.red)),
      ),
    );
  }
}

class _DetailView extends ConsumerWidget {
  final ContractDetailView detail;

  const _DetailView({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = detail.summary;
    final canDeclarePlan = s.status != ContractStatus.closed;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Back button + header ─────────────────────────────
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Voltar para lista',
                onPressed: () =>
                    ref.read(selectedContractIdProvider.notifier).state = null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      s.contractorName,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: s.status),
              const SizedBox(width: 16),
              if (canDeclarePlan)
                FilledButton.icon(
                  icon: const Icon(Icons.playlist_add_check, size: 16),
                  label: const Text('Declarar Plano'),
                  onPressed: () async {
                    final declared = await DeclareContractPlanForm.show(
                      context,
                      ref,
                      contractId: s.id,
                      contractName: s.name,
                      contractorName: s.contractorName,
                    );
                    if (declared == true) {
                      ref.invalidate(contractDetailProvider(s.id));
                      ref.invalidate(contractListProvider);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Metadata strip ───────────────────────────────────
          Wrap(
            spacing: 24,
            runSpacing: 4,
            children: [
              _MetaItem(
                label: 'Vigência',
                value:
                    '${_dateFormat.format(s.validFromUtc.toLocal())} – ${_dateFormat.format(s.validUntilUtc.toLocal())}',
              ),
              _MetaItem(
                label: 'Plano atual',
                value: s.activePlanVersion > 0 ? 'v${s.activePlanVersion}' : '—',
              ),
              _MetaItem(
                label: 'SETs pendentes',
                value: '${s.totalSetsInProgress}',
              ),
              _MetaItem(
                label: 'SLA health',
                value: '${s.slaHealthPercentage.toStringAsFixed(1)}%',
              ),
              if (s.activatedAtUtc != null)
                _MetaItem(
                  label: 'Ativado em',
                  value: _dateTimeFormat.format(s.activatedAtUtc!.toLocal()),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Tabs ─────────────────────────────────────────────
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'Viagens Programadas'),
                      Tab(text: 'Conciliação Financeira'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _ExecutionsTab(
                            executions: detail.recentExecutions),
                        _FinancialTab(financialSummary: detail.financialSummary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Executions Tab ────────────────────────────────────────────────────────────

class _ExecutionsTab extends StatelessWidget {
  final List<SlaExecutionItemView> executions;

  const _ExecutionsTab({required this.executions});

  @override
  Widget build(BuildContext context) {
    if (executions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_bus_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Nenhuma execução registrada.',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text('Declare um plano e aguarde telemetria.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 14,
          headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 12),
          columns: const [
            DataColumn(label: Text('SET ID')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Janela')),
            DataColumn(label: Text('Veículo')),
            DataColumn(label: Text('Valor'), numeric: true),
          ],
          rows: executions.map(_buildRow).toList(),
        ),
      ),
    );
  }

  DataRow _buildRow(SlaExecutionItemView e) {
    final window =
        '${_dateTimeFormat.format(e.windowStartUtc.toLocal())} – ${_dateTimeFormat.format(e.windowEndUtc.toLocal())}';
    return DataRow(cells: [
      DataCell(
        SelectableText('${e.setId.substring(0, 8)}…',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      ),
      DataCell(_ExecutionStatusChip(status: e.status)),
      DataCell(Text(window, style: const TextStyle(fontSize: 11))),
      DataCell(Text(e.boundVehicleId ?? e.plannedVehicleId ?? '—',
          style: const TextStyle(fontSize: 12))),
      DataCell(Text(
        _currencyFormat.format(e.contractualValue.toDouble()),
        style: const TextStyle(fontSize: 12),
      )),
    ]);
  }
}

// ── Financial Tab ─────────────────────────────────────────────────────────────

class _FinancialTab extends StatelessWidget {
  final dynamic financialSummary;

  const _FinancialTab({required this.financialSummary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _KpiCard(
            label: 'Receita Protegida',
            value: financialSummary.protectedRevenue,
            color: Colors.green,
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(width: 16),
          _KpiCard(
            label: 'Receita em Risco',
            value: financialSummary.revenueAtRisk,
            color: Colors.orange,
            icon: Icons.warning_amber_outlined,
          ),
          const SizedBox(width: 16),
          _KpiCard(
            label: 'Receita Perdida',
            value: financialSummary.lostRevenue,
            color: Colors.red,
            icon: Icons.money_off_outlined,
          ),
          const SizedBox(width: 16),
          _CountCard(
            label: 'Execuções',
            executed: financialSummary.totalExecuted,
            pending: financialSummary.totalPending,
            noShow: financialSummary.totalNoShow,
            gap: financialSummary.totalEvidenceGap,
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final Money value;
  final Color color;
  final IconData icon;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _currencyFormat.format(value.toDouble()),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  final String label;
  final int executed, pending, noShow, gap;

  const _CountCard({
    required this.label,
    required this.executed,
    required this.pending,
    required this.noShow,
    required this.gap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              _countRow('Executados', executed, Colors.green),
              _countRow('Pendentes', pending, Colors.blue),
              _countRow('No-show', noShow, Colors.red),
              _countRow('Gap evidência', gap, Colors.orange),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countRow(String lbl, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(lbl, style: const TextStyle(fontSize: 11)),
          const Spacer(),
          Text('$count',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final ContractStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ContractStatus.draft => ('Rascunho', Colors.blueGrey),
      ContractStatus.active => ('Ativo', Colors.green),
      ContractStatus.closed => ('Encerrado', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ExecutionStatusChip extends StatelessWidget {
  final ExecutionStatus status;

  const _ExecutionStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ExecutionStatus.pending => ('Pendente', Colors.blue),
      ExecutionStatus.executed => ('Executado', Colors.green),
      ExecutionStatus.noShow => ('No-show', Colors.red),
      ExecutionStatus.evidenceGap => ('Gap', Colors.orange),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final String label;
  final String value;

  const _MetaItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
