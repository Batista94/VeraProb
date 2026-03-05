import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:busflow/application/projections/providers/audit_filter_provider.dart';
import 'package:busflow/application/projections/providers/audit_log_projection_provider.dart';
import 'package:busflow/application/audit/audit_service.dart';
import 'package:busflow/core/theme/app_theme.dart';

class OperationalAuditScreen extends ConsumerWidget {
  const OperationalAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: BusFlowColors.background,
      appBar: AppBar(
        title: const Text(
          'OCC - Centro de Auditoria Integrada',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        backgroundColor: BusFlowColors.surface,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Usually handled automatically by the provider, but good for UX
              ref.invalidate(auditServiceProvider);
            },
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Side: Dense Table
          Expanded(
            flex: 7,
            child: Column(
              children: [
                _buildFilterBar(context, ref),
                const Divider(height: 1, color: BusFlowColors.border),
                _buildTableHeader(),
                const Divider(height: 1, color: BusFlowColors.border),
                Expanded(child: _buildLogTable(ref)),
              ],
            ),
          ),

          // Right Side: Master/Detail Panel
          const VerticalDivider(width: 1, color: BusFlowColors.border),
          const Expanded(flex: 3, child: _AuditSidePanel()),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(auditFilterProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: BusFlowColors.surface,
      child: Row(
        children: [
          // Just a mockup of OCC dense filters
          _FilterChip(
            label: filters.category ?? 'Todas Categorias',
            isActive: filters.category != null,
            onTap: () {
              ref
                  .read(auditFilterProvider.notifier)
                  .setCategory(
                    filters.category == 'SYSTEM' ? 'OPERATOR' : 'SYSTEM',
                  );
            },
            onClear: () =>
                ref.read(auditFilterProvider.notifier).clearCategory(),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Hoje',
            isActive: true,
            onTap: () {},
            onClear: null, // Immutable for now
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => ref.read(auditFilterProvider.notifier).clearAll(),
            icon: const Icon(Icons.clear_all, size: 16),
            label: const Text('Limpar Filtros', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: BusFlowColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: BusFlowColors.surfaceElevated,
      child: const Row(
        children: [
          SizedBox(width: 80, child: Text('HORA', style: _headerStyle)),
          SizedBox(
            width: 110,
            child: Text('CICLO DE VIDA', style: _headerStyle),
          ),
          SizedBox(width: 90, child: Text('CATEGORIA', style: _headerStyle)),
          Expanded(flex: 3, child: Text('AÇÃO', style: _headerStyle)),
          Expanded(flex: 2, child: Text('VEÍCULO', style: _headerStyle)),
          Expanded(flex: 2, child: Text('LINHA', style: _headerStyle)),
          SizedBox(width: 120, child: Text('AUTOR', style: _headerStyle)),
        ],
      ),
    );
  }

  Widget _buildLogTable(WidgetRef ref) {
    final projectionAsync = ref.watch(auditLogProjectionProvider);
    final selectedLog = ref.watch(selectedAuditLogProvider);

    return projectionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Text(
          'Erro ao carregar auditoria: $err',
          style: const TextStyle(color: BusFlowColors.error),
          textAlign: TextAlign.center,
        ),
      ),
      data: (projection) {
        if (projection.entries.isEmpty) {
          return const Center(
            child: Text(
              'Nenhum registro encontrado',
              style: TextStyle(color: BusFlowColors.textSecondary),
            ),
          );
        }

        return ListView.builder(
          itemCount: projection.entries.length,
          itemBuilder: (context, index) {
            final log = projection.entries[index];
            final isSelected = selectedLog?.id == log.id;

            return InkWell(
              onTap: () {
                ref.read(selectedAuditLogProvider.notifier).state = log;
              },
              child: Container(
                color: isSelected
                    ? BusFlowColors.primary.withValues(alpha: 0.1)
                    : (index.isEven
                          ? BusFlowColors.background
                          : BusFlowColors.surface),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        DateFormat('HH:mm:ss').format(log.timestamp),
                        style: _cellStyle.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: log.lifecycleStatus != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: log.lifecycleStatus!.color.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: log.lifecycleStatus!.color
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  log.lifecycleStatus!.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: log.lifecycleStatus!.color,
                                  ),
                                ),
                              )
                            : const Text(
                                '-',
                                style: TextStyle(
                                  color: BusFlowColors.textSecondary,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: log.category == 'SYSTEM'
                              ? BusFlowColors.info.withValues(alpha: 0.2)
                              : BusFlowColors.warning.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.category,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: log.category == 'SYSTEM'
                                ? BusFlowColors.info
                                : BusFlowColors.warning,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        log.action,
                        style: _cellStyle.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        log.vehiclePlate ?? '-',
                        style: _cellStyle.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(log.routeName ?? '-', style: _cellStyle),
                    ),
                    SizedBox(
                      width: 120,
                      child: Text(
                        log.actorName ?? '-',
                        style: _cellStyle.copyWith(
                          color: BusFlowColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? BusFlowColors.primary.withValues(alpha: 0.15)
              : BusFlowColors.background,
          border: Border.all(
            color: isActive
                ? BusFlowColors.primary.withValues(alpha: 0.5)
                : BusFlowColors.border,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive
                    ? BusFlowColors.primary
                    : BusFlowColors.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isActive && onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: BusFlowColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuditSidePanel extends ConsumerWidget {
  const _AuditSidePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(selectedAuditLogProvider);

    if (log == null) {
      return Container(
        color: BusFlowColors.surface,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 48, color: BusFlowColors.border),
              SizedBox(height: 16),
              Text(
                'Selecione um registro para ver os detalhes',
                style: TextStyle(color: BusFlowColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: BusFlowColors.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Detalhes do Registro',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: BusFlowColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () =>
                    ref.read(selectedAuditLogProvider.notifier).state = null,
                color: BusFlowColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 24),

          _DetailRow(label: 'ID', value: log.id, isMonospace: true),
          _DetailRow(
            label: 'Carimbo de Tempo',
            value: DateFormat('dd/MM/yyyy HH:mm:ss').format(log.timestamp),
          ),
          _DetailRow(label: 'Ação', value: log.action),
          _DetailRow(
            label: 'Autor',
            value: '${log.actorName} (${log.actorId})',
          ),

          const Divider(height: 32, color: BusFlowColors.border),
          const Text(
            'Contexto da Entidade',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: BusFlowColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          _DetailRow(
            label: 'Veículo/Placa',
            value: log.vehiclePlate ?? 'Não aplicável',
          ),
          _DetailRow(label: 'Linha', value: log.routeName ?? 'Não aplicável'),
          _DetailRow(
            label: 'Status no Momento',
            value: log.statusLabel ?? 'Desconhecido',
          ),
          if (log.lifecycleStatus != null)
            _DetailRow(
              label: 'Ciclo de Vida',
              value: log.lifecycleStatus!.label,
            ),

          if (log.details != null) ...[
            const Divider(height: 32, color: BusFlowColors.border),
            const Text(
              'Carga Útil / Razão',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: BusFlowColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BusFlowColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BusFlowColors.border),
              ),
              child: Text(
                log.details!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: BusFlowColors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isMonospace;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isMonospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: BusFlowColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: BusFlowColors.textPrimary,
                fontFamily: isMonospace ? 'monospace' : null,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _headerStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.bold,
  color: BusFlowColors.textSecondary,
  letterSpacing: 0.5,
);

const _cellStyle = TextStyle(fontSize: 13, color: BusFlowColors.textPrimary);
