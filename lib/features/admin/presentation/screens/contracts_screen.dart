import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:busflow/application/sla_audit/projections/contract_summary_view.dart';
import 'package:busflow/domain/sla_audit/contract_status.dart';
import 'package:busflow/state/providers/contract_providers.dart';
import 'package:busflow/core/theme/app_theme.dart';

import 'create_contract_form.dart';
import 'contract_detail_screen.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');

class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedContractIdProvider);

    if (selectedId != null) {
      return ContractDetailScreen(contractId: selectedId);
    }

    return const _ContractListView();
  }
}

class _ContractListView extends ConsumerWidget {
  const _ContractListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(contractListProvider);
    final activeFilter = ref.watch(contractStatusFilterProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestão de Contratos',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: BusFlowColors.textPrimary,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'Controle de vigência e conformidade SLA',
                    style: TextStyle(color: BusFlowColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Novo Contrato'),
                onPressed: () async {
                  final newContractId = await CreateContractForm.show(context, ref);
                  if (newContractId != null) {
                    ref.invalidate(contractListProvider);
                    ref.read(selectedContractIdProvider.notifier).state = newContractId;
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 32),

          Wrap(
            spacing: 12,
            children: [
              _FilterChip(
                label: 'Todos',
                selected: activeFilter == null,
                onSelected: (_) => ref
                    .read(contractStatusFilterProvider.notifier)
                    .state = null,
              ),
              _FilterChip(
                label: 'Rascunhos',
                color: BusFlowColors.neutral,
                selected: activeFilter == ContractStatus.draft,
                onSelected: (_) => ref
                    .read(contractStatusFilterProvider.notifier)
                    .state = ContractStatus.draft,
              ),
              _FilterChip(
                label: 'Ativos',
                color: BusFlowColors.success,
                selected: activeFilter == ContractStatus.active,
                onSelected: (_) => ref
                    .read(contractStatusFilterProvider.notifier)
                    .state = ContractStatus.active,
              ),
              _FilterChip(
                label: 'Encerrados',
                color: BusFlowColors.error,
                selected: activeFilter == ContractStatus.closed,
                onSelected: (_) => ref
                    .read(contractStatusFilterProvider.notifier)
                    .state = ContractStatus.closed,
              ),
            ],
          ),
          const SizedBox(height: 24),

          Expanded(
            child: contractsAsync.when(
              data: (contracts) => contracts.isEmpty
                  ? const _EmptyState()
                  : _ContractTable(contracts: contracts),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar contratos: $e',
                  style: const TextStyle(color: BusFlowColors.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractTable extends ConsumerWidget {
  final List<ContractSummaryView> contracts;
  const _ContractTable({required this.contracts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          child: DataTable(
            columnSpacing: 24,
            headingRowColor: WidgetStateProperty.all(BusFlowColors.surfaceElevated),
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: BusFlowColors.textSecondary,
              letterSpacing: 0.5,
            ),
            dataRowMaxHeight: 64,
            rows: contracts.map((c) => _buildRow(context, ref, c)).toList(),
            columns: const [
              DataColumn(label: Text('CONTRATO')),
              DataColumn(label: Text('CONTRATANTE')),
              DataColumn(label: Text('VIGÊNCIA')),
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('SAÚDE SLA')),
              DataColumn(label: Text('')),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, WidgetRef ref, ContractSummaryView c) {
    final vigencia =
        '${_dateFormat.format(c.validFromUtc.toLocal())} – ${_dateFormat.format(c.validUntilUtc.toLocal())}';

    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, color: BusFlowColors.textPrimary)),
              if (c.activePlanVersion > 0)
                Text('Plano v${c.activePlanVersion}', style: const TextStyle(fontSize: 11, color: BusFlowColors.textSecondary)),
            ],
          ),
        ),
        DataCell(Text(c.contractorName, style: const TextStyle(color: BusFlowColors.textPrimary))),
        DataCell(Text(vigencia, style: const TextStyle(fontSize: 12, color: BusFlowColors.textSecondary))),
        DataCell(_StatusChip(status: c.status)),
        DataCell(_SlaHealthBar(percentage: c.slaHealthPercentage)),
        DataCell(
          TextButton(
            onPressed: () {
              ref.read(selectedContractIdProvider.notifier).state = c.id;
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Gerenciar'),
                SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final ValueChanged<bool> onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? BusFlowColors.primary;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: effectiveColor.withValues(alpha: 0.2),
      checkmarkColor: effectiveColor,
      labelStyle: TextStyle(
        color: selected ? effectiveColor : BusFlowColors.textSecondary,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: selected ? effectiveColor : BusFlowColors.border,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ContractStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ContractStatus.draft => ('RASCUNHO', BusFlowColors.neutral),
      ContractStatus.active => ('ATIVO', BusFlowColors.success),
      ContractStatus.closed => ('ENCERRADO', BusFlowColors.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
}

class _SlaHealthBar extends StatelessWidget {
  final double percentage;
  const _SlaHealthBar({required this.percentage});

  @override
  Widget build(BuildContext context) {
    final pct = percentage.clamp(0.0, 100.0);
    final color = pct >= 90 ? BusFlowColors.success : pct >= 70 ? BusFlowColors.warning : BusFlowColors.error;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${pct.toStringAsFixed(0)}%', 
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 4,
                  backgroundColor: BusFlowColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 80, color: BusFlowColors.border),
          const SizedBox(height: 24),
          const Text('Nenhum contrato encontrado', 
            style: TextStyle(color: BusFlowColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Crie um novo contrato para iniciar a auditoria de SLA.', 
            style: TextStyle(color: BusFlowColors.textSecondary)),
        ],
      ),
    );
  }
}
