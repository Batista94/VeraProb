import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/projections/models/audit_log_projection.dart';
import 'package:veraprob/application/projections/providers/audit_filter_provider.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/orphan_triage_tab.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/roi_guardian_strip.dart';
import 'dart:math' as math;

import 'package:veraprob/features/shared/mappers/incident_status_ui_mapper.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/audit_providers.dart';
import 'package:veraprob/state/providers/shadow_providers.dart';

class OperationalAuditScreen extends ConsumerStatefulWidget {
  const OperationalAuditScreen({super.key});

  @override
  ConsumerState<OperationalAuditScreen> createState() =>
      _OperationalAuditScreenState();
}

class _OperationalAuditScreenState
    extends ConsumerState<OperationalAuditScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: VeraProbColors.background,
        // QA/Security: drawer sob demanda para todos os tamanhos de tela
        endDrawer: Drawer(
          width: math.min(480.0, screenWidth * 0.45),
          backgroundColor: VeraProbColors.surface,
          child: SafeArea(
            child: Column(
              children: [
                // Drawer header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: VeraProbColors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: VeraProbColors.primary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Detalhes do Registro',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: VeraProbColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          Navigator.pop(context);
                          ref.read(selectedAuditLogProvider.notifier).set(null);
                        },
                        color: VeraProbColors.textSecondary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: _AuditSidePanel()),
              ],
            ),
          ),
        ),
        // De-chromed: the admin shell already provides the AppBar. A local
        // AppBar here would render double chrome (P3, shell overhaul).
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VeraProbSpacing.lg,
                VeraProbSpacing.md,
                VeraProbSpacing.lg,
                VeraProbSpacing.md,
              ),
              child: VeraProbHeader(
                icon: Icons.fact_check_outlined,
                title: 'OCC - Centro de Auditoria Integrada',
                actions: [
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    tooltip: 'Detalhes do Registro',
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Atualizar registros',
                    onPressed: () {
                      ref.invalidate(auditServiceProvider);
                      ref.invalidate(unlinkedShadowsProvider);
                    },
                  ),
                ],
              ),
            ),
            const RoiGuardianStrip(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tabbed content (audit + orphan triage) full width
                  Expanded(
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
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [
                              Tab(text: '📋 Fila de Exceções'),
                              Tab(text: '🔗 Execuções Não Reconciliadas'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _AuditTab(
                                onOpenDrawer: () =>
                                    _scaffoldKey.currentState?.openEndDrawer(),
                              ),
                              const OrphanTriageTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditTab extends ConsumerWidget {
  final VoidCallback onOpenDrawer;

  const _AuditTab({required this.onOpenDrawer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _buildFilterBar(context, ref),
        const Divider(height: 1, color: VeraProbColors.border),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 1000,
                    maxWidth: math.max(constraints.maxWidth, 1000),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTableHeader(),
                      const Divider(height: 1, color: VeraProbColors.border),
                      Expanded(child: _buildLogTable(ref)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(auditFilterProvider);

    // Horizontal scroll prevents filter chips from overflowing on narrow screens
    return Container(
      color: VeraProbColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _FilterChip(
              label: filters.silentMode ? '⚠️ Apenas Exceções' : '📢 Ver Tudo',
              isActive: filters.silentMode,
              onTap: () =>
                  ref.read(auditFilterProvider.notifier).toggleSilentMode(),
              onClear: null,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: filters.category == 'SYSTEM'
                  ? 'Sistema'
                  : (filters.category == 'OPERATOR'
                        ? 'Operador'
                        : 'Todas Categorias'),
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
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: () =>
                  ref.read(auditFilterProvider.notifier).clearAll(),
              icon: const Icon(Icons.clear_all, size: 16),
              label: const Text(
                'Limpar Filtros',
                style: TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: VeraProbColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: VeraProbColors.surfaceElevated,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text('Hora', style: _headerStyle)),
            Expanded(
              flex: 3,
              child: Text('Ciclo de Vida', style: _headerStyle),
            ),
            Expanded(flex: 2, child: Text('Categoria', style: _headerStyle)),
            Expanded(flex: 5, child: Text('Ação', style: _headerStyle)),
            Expanded(flex: 3, child: Text('Veículo', style: _headerStyle)),
            Expanded(flex: 3, child: Text('Rota', style: _headerStyle)),
            Expanded(
              flex: 3,
              child: Text('Autor / Sistema', style: _headerStyle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowItem(
    BuildContext context,
    WidgetRef ref,
    AuditLogEntry log,
    int index,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () {
        ref.read(selectedAuditLogProvider.notifier).set(log);
        onOpenDrawer();
      },
      child: Container(
        color: isSelected
            ? VeraProbColors.primary.withValues(alpha: 0.1)
            : (index.isEven
                  ? VeraProbColors.background
                  : VeraProbColors.surface),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('HH:mm:ss').format(log.timestamp.toLocal()),
                    style: _cellStyle.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Text(
                    'Local',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: VeraProbColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
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
                        style: TextStyle(color: VeraProbColors.textSecondary),
                      ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: log.category == 'SYSTEM'
                        ? VeraProbColors.info.withValues(alpha: 0.15)
                        : VeraProbColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.category == 'SYSTEM' ? 'Sistema' : 'Operador',
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
            ),
            Expanded(
              flex: 5,
              child: Text(
                _translateAction(log.action),
                style: _cellStyle.copyWith(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                log.vehiclePlate ?? '-',
                style: _cellStyle.copyWith(fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                log.routeName ?? '-',
                style: _cellStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                log.actorName ?? '-',
                style: _cellStyle.copyWith(color: VeraProbColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogTable(WidgetRef ref) {
    final projectionAsync = ref.watch(auditLogProjectionProvider);
    final selectedLog = ref.watch(selectedAuditLogProvider);
    final filters = ref.watch(auditFilterProvider);

    return switch (projectionAsync) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError() => const Center(
        child: Text(
          'Não foi possível carregar os registros de auditoria.',
          style: TextStyle(color: VeraProbColors.error),
          textAlign: TextAlign.center,
        ),
      ),
      AsyncData(:final value) => _buildAuditContent(
        value,
        filters,
        selectedLog,
        ref,
      ),
    };
  }

  Widget _buildAuditContent(
    AuditLogProjection value,
    AuditFilterState filters,
    AuditLogEntry? selectedLog,
    WidgetRef ref,
  ) {
    if (value.entries.isEmpty) {
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
      itemCount: value.entries.length,
      itemBuilder: (context, index) {
        final log = value.entries[index];
        final isSelected = selectedLog?.id == log.id;
        return _buildRowItem(context, ref, log, index, isSelected);
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
              label: 'ID',
              value: log.id,
              isMonospace: true,
              isCopyable: true,
            ),
            _DetailRow(
              label: 'Timestamp UTC',
              value: DateFormat('dd/MM/yyyy HH:mm:ss').format(log.timestamp),
            ),
            _DetailRow(
              label: 'Tempo Local',
              value: DateFormat(
                'dd/MM/yyyy HH:mm:ss',
              ).format(log.timestamp.toLocal()),
            ),
            _DetailRow(
              label: 'Ação',
              value: _translateAction(log.action),
              isCopyable: true,
            ),
            _DetailRow(
              label: 'Autor',
              value: '${log.actorName ?? 'N/D'} (${log.actorId})',
              isCopyable: true,
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
              isCopyable: log.vehiclePlate != null,
            ),
            _DetailRow(
              label: 'Rota',
              value: log.routeName ?? 'Não aplicável',
              isCopyable: log.routeName != null,
            ),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Carga Útil / Razão',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: VeraProbColors.textSecondary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_all, size: 16),
                    tooltip: 'Copiar Carga Útil',
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(text: log.details!),
                      );
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Carga útil copiada para a área de transferência',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    color: VeraProbColors.textSecondary,
                  ),
                ],
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
                child: SelectableText(
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
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isMonospace;
  final bool isCopyable;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isMonospace = false,
    this.isCopyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: VeraProbColors.textPrimary,
                    fontFamily: isMonospace ? 'monospace' : null,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (isCopyable &&
                  value != 'Não aplicável' &&
                  value.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 14),
                  tooltip: 'Copiar para a área de transferência',
                  color: VeraProbColors.textSecondary,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: value));
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Copiado para a área de transferência'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

String _translateAction(String action) {
  switch (action.toUpperCase()) {
    case 'VERDICT_REFUSED':
      return 'Veredito Recusado';
    case 'VERDICT_SEALED':
      return 'Veredito Selado';
    case 'SANCTION_RECOMMENDED':
      return 'Sanção Recomendada';
    case 'SANCTION_DISPUTED':
      return 'Sanção Contestada';
    case 'DISPUTE_ACCEPTED':
      return 'Contestação Aceita';
    case 'DISPUTE_OVERTURNED':
      return 'Contestação Anulada';
    case 'DISPUTE_RETRACTED':
      return 'Contestação Retirada';
    case 'CONTRACT_CREATED':
      return 'Contrato Criado';
    case 'CONTRACT_ACTIVATED':
      return 'Contrato Ativado';
    case 'CONTRACT_CLOSED':
      return 'Contrato Fechado';
    case 'CONTRACT_SUBMITTED_FOR_APPROVAL':
      return 'Contrato Submetido para Aprovação';
    case 'CONTRACT_ACCEPTED_BY_CONTRACTOR':
      return 'Contrato Aceito pela Contratada';
    case 'EXECUTION_BOUND':
      return 'Serviço Vinculado';
    case 'NO_SHOW_DECLARED':
      return 'No-Show Declarado';
    case 'EVIDENCE_GAP_DECLARED':
      return 'Lacuna de Evidência';
    case 'TRANSIT_STARTED':
      return 'Trânsito Iniciado';
    case 'COMPLETED_WITH_GAPS':
      return 'Concluído com Lacunas';
    case 'EXECUTION_INHIBITED':
      return 'Execução Inibida';
    case 'OCCURRENCE_REGISTERED':
      return 'Ocorrência Registrada';
    case 'TRIP_INTERRUPTED':
      return 'Viagem Interrompida';
    case 'TRIP_CANCELLED':
      return 'Viagem Cancelada';
    case 'JUSTIFICATION_SUBMITTED':
      return 'Justificativa Submetida';
    case 'JUSTIFICATION_APPROVED':
      return 'Justificativa Aprovada';
    case 'JUSTIFICATION_REJECTED':
      return 'Justificativa Rejeitada';
    case 'SLA_JUSTIFICATION_SUBMITTED':
      return 'Justificativa de SLA Submetida';
    case 'SLA_JUSTIFICATION_EXPIRED':
      return 'Justificativa de SLA Expirada';
    default:
      return action.replaceAll('_', ' ');
  }
}

const _headerStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.bold,
  color: VeraProbColors.textSecondary,
  letterSpacing: 0.5,
);

const _cellStyle = TextStyle(fontSize: 13, color: VeraProbColors.textPrimary);
