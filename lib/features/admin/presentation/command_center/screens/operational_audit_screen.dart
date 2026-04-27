import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/projections/providers/audit_filter_provider.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/orphan_triage_tab.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/roi_guardian_strip.dart';
import 'package:veraprob/features/admin/presentation/screens/create_execution_dialog.dart';
import 'package:veraprob/features/shared/mappers/incident_status_ui_mapper.dart';
import 'package:veraprob/state/providers/audit_providers.dart';

class OperationalAuditScreen extends ConsumerWidget {
  const OperationalAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: VeraProbColors.background,
        appBar: AppBar(
          title: const Text(
            'OCC - Centro de Auditoria Integrada',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
          ),
          backgroundColor: VeraProbColors.surface,
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(auditServiceProvider);
                ref.invalidate(unlinkedShadowsProvider);
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add_road_outlined),
          label: const Text('Nova Viagem'),
          backgroundColor: VeraProbColors.primary,
          onPressed: () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const CreateExecutionDialog(),
          ),
        ),
        body: Column(
          children: [
            const RoiGuardianStrip(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left: tabbed content (audit + orphan triage)
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        Container(
                          color: VeraProbColors.surface,
                          child: const TabBar(
                            indicatorColor: VeraProbColors.primary,
                            labelColor: VeraProbColors.primary,
                            unselectedLabelColor: VeraProbColors.textSecondary,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            tabs: [
                              Tab(text: '📋 Fila de Exceções'),
                              Tab(text: '🔗 Triagem de Órfãos'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [_AuditTab(), const OrphanTriageTab()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1, color: VeraProbColors.border),
                  const Expanded(flex: 3, child: _AuditSidePanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The original audit log tab — extracted for TabBarView.
class _AuditTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _buildFilterBar(context, ref),
        const Divider(height: 1, color: VeraProbColors.border),
        _buildTableHeader(),
        const Divider(height: 1, color: VeraProbColors.border),
        Expanded(child: _buildLogTable(ref)),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(auditFilterProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: VeraProbColors.surface,
      child: Row(
        children: [
          _FilterChip(
            label: filters.silentMode ? '🔇 Modo Silencioso' : '📢 Ver Tudo',
            isActive: filters.silentMode,
            onTap: () =>
                ref.read(auditFilterProvider.notifier).toggleSilentMode(),
            onClear: null,
          ),
          const SizedBox(width: 8),
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
            onClear: null,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => ref.read(auditFilterProvider.notifier).clearAll(),
            icon: const Icon(Icons.clear_all, size: 16),
            label: const Text('Limpar Filtros', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: VeraProbColors.surfaceElevated,
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
          Expanded(flex: 2, child: Text('ROTA', style: _headerStyle)),
          SizedBox(width: 120, child: Text('AUTOR', style: _headerStyle)),
        ],
      ),
    );
  }

  Widget _buildLogTable(WidgetRef ref) {
    final projectionAsync = ref.watch(auditLogProjectionProvider);
    final selectedLog = ref.watch(selectedAuditLogProvider);
    final filters = ref.watch(auditFilterProvider);

    return projectionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Text(
          'Erro ao carregar auditoria: $err',
          style: const TextStyle(color: VeraProbColors.error),
          textAlign: TextAlign.center,
        ),
      ),
      data: (projection) {
        if (projection.entries.isEmpty) {
          if (filters.silentMode) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: VeraProbColors.success,
                  ),
                  SizedBox(height: 12),
                  Text(
                    '✅ Nenhuma exceção ativa',
                    style: TextStyle(
                      color: VeraProbColors.success,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Todas as viagens estão dentro dos parâmetros',
                    style: TextStyle(
                      color: VeraProbColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }
          return const Center(
            child: Text(
              'Nenhum registro encontrado',
              style: TextStyle(color: VeraProbColors.textSecondary),
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
                    ? VeraProbColors.primary.withValues(alpha: 0.1)
                    : (index.isEven
                          ? VeraProbColors.background
                          : VeraProbColors.surface),
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
                                  color: IncidentStatusUiMapper.colorFor(
                                    log.lifecycleStatus!,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: IncidentStatusUiMapper.colorFor(
                                      log.lifecycleStatus!,
                                    ).withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  log.lifecycleStatus!.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: IncidentStatusUiMapper.colorFor(
                                      log.lifecycleStatus!,
                                    ),
                                  ),
                                ),
                              )
                            : const Text(
                                '-',
                                style: TextStyle(
                                  color: VeraProbColors.textSecondary,
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
                              ? VeraProbColors.info.withValues(alpha: 0.2)
                              : VeraProbColors.warning.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.category,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: log.category == 'SYSTEM'
                                ? VeraProbColors.info
                                : VeraProbColors.warning,
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
                          color: VeraProbColors.textSecondary,
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
              ? VeraProbColors.primary.withValues(alpha: 0.15)
              : VeraProbColors.background,
          border: Border.all(
            color: isActive
                ? VeraProbColors.primary.withValues(alpha: 0.5)
                : VeraProbColors.border,
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
                    ? VeraProbColors.primary
                    : VeraProbColors.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isActive && onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: VeraProbColors.primary,
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
        color: VeraProbColors.surface,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 48, color: VeraProbColors.border),
              SizedBox(height: 16),
              Text(
                'Selecione um registro para ver os detalhes',
                style: TextStyle(color: VeraProbColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: VeraProbColors.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Detalhes do Registro',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: VeraProbColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () =>
                    ref.read(selectedAuditLogProvider.notifier).state = null,
                color: VeraProbColors.textSecondary,
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
            value: '${log.actorName ?? 'N/D'} (${log.actorId})',
          ),
          const Divider(height: 32, color: VeraProbColors.border),
          const Text(
            'Contexto da Entidade',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            label: 'Veículo/Placa',
            value: log.vehiclePlate ?? 'Não aplicável',
          ),
          _DetailRow(label: 'Rota', value: log.routeName ?? 'Não aplicável'),
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
            const Divider(height: 32, color: VeraProbColors.border),
            const Text(
              'Carga Útil / Razão',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VeraProbColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: VeraProbColors.border),
              ),
              child: Text(
                log.details!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: VeraProbColors.textPrimary,
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
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: VeraProbColors.textPrimary,
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
  color: VeraProbColors.textSecondary,
  letterSpacing: 0.5,
);

const _cellStyle = TextStyle(fontSize: 13, color: VeraProbColors.textPrimary);
