import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:busflow/domain/sla_audit/execution_status.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

class SlaExecutionDetailDrawer extends StatelessWidget {
  final SlaExecutionItemView item;

  const SlaExecutionDetailDrawer({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 400,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: BusFlowColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(onClose: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusSection(status: item.status),
                    const SizedBox(height: 32),
                    _InfoField(label: 'SET ID', value: item.setId),
                    _InfoField(label: 'Contrato', value: item.contractId),
                    _InfoField(
                      label: 'Janela Operacional',
                      value:
                          '${_formatFull(item.windowStartUtc)} - ${_formatFull(item.windowEndUtc)} UTC',
                    ),
                    _InfoField(
                      label: 'Veículo Planejado',
                      value: item.plannedVehicleId ?? 'Qualquer veículo',
                    ),
                    const Divider(height: 48),
                    const Text(
                      'DADOS FINANCEIROS',
                      style: BusFlowTypography.caption,
                    ),
                    const SizedBox(height: 16),
                    _InfoField(
                      label: 'Valor Contratual',
                      value: _currencyFormat.format(item.contractualValue),
                    ),
                    _InfoField(
                      label: 'Multiplicador NoShow',
                      value: '${item.noShowPenaltyMultiplier}x',
                    ),
                    if (item.status == ExecutionStatus.noShow)
                      _InfoField(
                        label: 'Penalidade Calculada',
                        value: _currencyFormat.format(
                          item.contractualValue * item.noShowPenaltyMultiplier,
                        ),
                      ),
                    const Divider(height: 48),
                    const Text(
                      'GEOFENCE DE PARTIDA',
                      style: BusFlowTypography.caption,
                    ),
                    const SizedBox(height: 16),
                    _InfoField(
                      label: 'Coordenadas',
                      value:
                          '${item.startLatitude.toStringAsFixed(6)}, ${item.startLongitude.toStringAsFixed(6)}',
                    ),
                    _InfoField(
                      label: 'Raio de Detecção',
                      value: '${item.startRadiusMeters} metros',
                    ),
                    if (item.status == ExecutionStatus.executed) ...[
                      const Divider(height: 48),
                      const Text(
                        'EVIDÊNCIA DE EXECUÇÃO',
                        style: BusFlowTypography.caption,
                      ),
                      const SizedBox(height: 16),
                      _InfoField(
                        label: 'Veículo Efetivo',
                        value: item.boundVehicleId ?? 'Desconhecido',
                      ),
                      _InfoField(
                        label: 'Horário de Binding',
                        value: item.boundAtUtc != null
                            ? _formatFull(item.boundAtUtc!)
                            : '-',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFull(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;

  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: BusFlowColors.border.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Detalhes da Obrigação',
            style: BusFlowTypography.sectionTitle,
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  final ExecutionStatus status;

  const _StatusSection({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final String description;

    switch (status) {
      case ExecutionStatus.noShow:
        color = BusFlowColors.error;
        label = 'NO SHOW';
        description = 'Nenhum veículo detectado na geofence durante a janela.';
      case ExecutionStatus.evidenceGap:
        color = BusFlowColors.warning;
        label = 'EVIDENCE GAP';
        description = 'Veículo detectado, mas permanência foi insuficiente.';
      case ExecutionStatus.executed:
        color = BusFlowColors.success;
        label = 'EXECUTADO';
        description = 'Obrigação cumprida conforme contrato.';
      case ExecutionStatus.pending:
        color = BusFlowColors.textSecondary;
        label = 'PENDENTE';
        description = 'Aguardando encerramento da janela.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: BusFlowTypography.badge.copyWith(color: color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: BusFlowTypography.bodyMedium.copyWith(
            color: BusFlowColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _InfoField extends StatelessWidget {
  final String label;
  final String value;

  const _InfoField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: BusFlowTypography.caption.copyWith(
              color: BusFlowColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: BusFlowTypography.bodyMedium),
        ],
      ),
    );
  }
}
