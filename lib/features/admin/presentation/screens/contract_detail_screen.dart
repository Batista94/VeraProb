import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/sla_audit/projections/contract_detail_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/application/sla_audit/submit_contract_for_approval_command.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/presentation/shared/ui/veraprob_header.dart';
import 'package:veraprob/presentation/shared/ui/veraprob_chip.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/widgets/contract_amendments_timeline.dart';

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

    return switch (detailAsync) {
      AsyncData(:final value) => () {
        if (value == null) {
          return const Center(child: Text('Contrato não encontrado.'));
        }
        return _DetailView(detail: value);
      }(),
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => Center(
        child: Text(
          'Erro ao carregar contrato: $error',
          style: const TextStyle(color: VeraProbColors.error),
        ),
      ),
    };
  }
}

class _DetailView extends ConsumerStatefulWidget {
  final ContractDetailView detail;

  const _DetailView({required this.detail});

  @override
  ConsumerState<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends ConsumerState<_DetailView> {
  bool _submitting = false;

  Future<void> _submitForApproval(BuildContext context) async {
    final s = widget.detail.summary;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enviar para Aprovação'),
        content: Text(
          'Deseja enviar o contrato "${s.name}" para aprovação do contratante?\n\n'
          'Um link de revisão será gerado e o contrato ficará bloqueado até o aceite.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);

    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final userId = ref.read(currentOperatorIdProvider);
      final role = ref.read(currentUserRoleProvider);
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      if (orgId == null || userId == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sessão inválida. Faça login novamente.'),
          ),
        );
        return;
      }

      final token = await ref
          .read(submitContractForApprovalHandlerProvider)
          .handle(
            SubmitContractForApprovalCommand(
              organizationId: orgId,
              contractId: s.id,
              callerUserId: userId,
              callerRole: role,
              sessionId: sessionId,
            ),
          );

      ref.invalidate(contractDetailProvider(s.id));
      ref.invalidate(contractListProvider);

      if (!mounted) return;

      // Build the review link based on current window location
      final baseUri = Uri.base;
      final origin = (baseUri.scheme == 'http' || baseUri.scheme == 'https')
          ? baseUri.origin
          : 'http://localhost:3000';
      final reviewLink = '$origin/review-contract?token=$token';

      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Link de Revisão Gerado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Compartilhe o link abaixo com o contratante.\n'
                'Válido por 30 dias.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: VeraProbColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VeraProbColors.border),
                ),
                child: SelectableText(
                  reviewLink,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copiar Link'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: reviewLink));
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Link copiado!')));
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (e) {
      final raw = e.toString();
      final isUnauthorized =
          raw.contains('Unauthorized') || raw.contains('unauthorized');
      final msg = isUnauthorized
          ? 'Permissão negada. Faça logout e login novamente para atualizar suas credenciais.'
          : raw.replaceAll('Exception: ', '');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: VeraProbColors.error),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.detail.summary;
    final canDeclarePlan =
        s.status != ContractStatusView.closed &&
        s.status != ContractStatusView.awaitingContractorAcceptance;
    final noPlan =
        s.status == ContractStatusView.draft && s.activePlanVersion == 0;
    final canSubmitForApproval =
        s.status == ContractStatusView.draft && s.activePlanVersion > 0;

    return Padding(
      padding: const EdgeInsets.all(VeraProbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Back button + header ─────────────────────────────
          VeraProbHeader(
            icon: Icons.description_outlined,
            title: s.name,
            subtitle: s.contractorName,
            actions: [
              _StatusChip(status: s.status),
              const SizedBox(width: VeraProbSpacing.md),
              OutlinedButton.icon(
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Regras SLA'),
                onPressed: () => context.go(AppRoutes.contractRules(s.id)),
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              if (canSubmitForApproval)
                OutlinedButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 16),
                  label: const Text('Enviar para Aprovação'),
                  onPressed: _submitting
                      ? null
                      : () => _submitForApproval(context),
                ),
              if (canSubmitForApproval)
                const SizedBox(width: VeraProbSpacing.sm),
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
                      // ignore: unused_result
                      await ref.refresh(contractDetailProvider(s.id).future);
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
                value: s.activePlanVersion > 0
                    ? 'v${s.activePlanVersion}'
                    : '—',
              ),
              _MetaItem(
                label: 'SETs pendentes',
                value: '${s.totalSetsInProgress}',
              ),
              _MetaItem(
                label: 'SLA health',
                value: '${(s.slaHealthBps / 100).toStringAsFixed(1)}%',
              ),
              if (s.activatedAtUtc != null)
                _MetaItem(
                  label: 'Ativado em',
                  value: _dateTimeFormat.format(s.activatedAtUtc!.toLocal()),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Forensic Seal (INV-34) ───────────────────────────
          if (s.previousHash != null || s.currentHash != null)
            _ForensicSealSection(
              previousHash: s.previousHash,
              currentHash: s.currentHash,
            ),
          if (s.previousHash != null || s.currentHash != null)
            const SizedBox(height: 16),

          // ── No-plan guidance banner ───────────────────────────
          if (noPlan)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: VeraProbColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: VeraProbColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: VeraProbColors.warning,
                    size: 18,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nenhum Plano Operacional declarado. Declare um plano antes de enviar para aprovação.',
                      style: TextStyle(
                        fontSize: 13,
                        color: VeraProbColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),

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
                          executions: widget.detail.recentExecutions,
                          activePlanVersion: s.activePlanVersion,
                          contractId: s.id,
                        ),
                        _FinancialTab(
                          financialSummary: widget.detail.financialSummary,
                          contractId: s.id,
                        ),
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

class _ExecutionsTab extends ConsumerStatefulWidget {
  final List<SlaExecutionItemView> executions;
  final int activePlanVersion;
  final String contractId;

  const _ExecutionsTab({
    required this.executions,
    required this.activePlanVersion,
    required this.contractId,
  });

  @override
  ConsumerState<_ExecutionsTab> createState() => _ExecutionsTabState();
}

class _ExecutionsTabState extends ConsumerState<_ExecutionsTab> {
  Timer? _pollTimer;
  int _pollCount = 0;
  bool _giveUp = false;

  @override
  void initState() {
    super.initState();
    _startPollingIfNeeded();
  }

  @override
  void didUpdateWidget(_ExecutionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activePlanVersion != oldWidget.activePlanVersion) {
      _stopPolling();
      _pollCount = 0;
      _giveUp = false;
    }
    if (widget.executions.isNotEmpty) {
      _stopPolling();
      _pollCount = 0;
      _giveUp = false;
    } else {
      _startPollingIfNeeded();
    }
  }

  void _startPollingIfNeeded() {
    if (widget.executions.isEmpty &&
        widget.activePlanVersion > 0 &&
        !_giveUp &&
        _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_pollCount < 5) {
          _pollCount++;
          ref.invalidate(contractDetailProvider(widget.contractId));
        } else {
          _stopPolling();
          setState(() {
            _giveUp = true;
          });
        }
      });
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.executions.isEmpty) {
      if (widget.activePlanVersion > 0 && !_giveUp) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Processando malha horária do plano...',
                style: TextStyle(
                  color: VeraProbColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }

      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_bus_outlined,
              size: 48,
              color: VeraProbColors.textDisabled,
            ),
            SizedBox(height: 12),
            Text(
              'Nenhuma viagem projetada.',
              style: TextStyle(color: VeraProbColors.textSecondary),
            ),
            SizedBox(height: 4),
            Text(
              'Declare um plano operacional para começar o monitoramento.',
              style: TextStyle(
                color: VeraProbColors.textDisabled,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columnSpacing: 14,
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              columns: const [
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Janela')),
                DataColumn(label: Text('Veículo')),
                DataColumn(label: Text('Valor'), numeric: true),
              ],
              rows: widget.executions.map(_buildRow).toList(),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(SlaExecutionItemView e) {
    final window =
        '${_dateTimeFormat.format(e.windowStartUtc.toLocal())} – ${_dateTimeFormat.format(e.windowEndUtc.toLocal())}';
    return DataRow(
      cells: [
        DataCell(_ExecutionStatusChip(status: e.status)),
        DataCell(Text(window, style: const TextStyle(fontSize: 11))),
        DataCell(
          Text(
            e.boundVehicleId ?? e.plannedVehicleId ?? 'Sem veículo',
            style: TextStyle(
              fontSize: 12,
              color: (e.boundVehicleId == null && e.plannedVehicleId == null)
                  ? VeraProbColors.textDisabled
                  : null,
            ),
          ),
        ),
        DataCell(
          Text(
            _currencyFormat.format(e.contractualValue / 100.0),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ── Financial Tab ─────────────────────────────────────────────────────────────

class _FinancialTab extends StatelessWidget {
  final SlaExecutionSummary financialSummary;
  final String contractId;

  const _FinancialTab({
    required this.financialSummary,
    required this.contractId,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _KpiCard(
                label: 'Receita Protegida',
                value: financialSummary.protectedRevenue,
                color: VeraProbColors.onTime,
                icon: Icons.check_circle_outline,
              ),
              _KpiCard(
                label: 'Receita em Risco',
                value: financialSummary.revenueAtRisk,
                color: VeraProbColors.warning,
                icon: Icons.warning_amber_outlined,
              ),
              _KpiCard(
                label: 'Receita Perdida',
                value: financialSummary.lostRevenue,
                color: VeraProbColors.error,
                icon: Icons.money_off_outlined,
              ),
              _CountCard(
                label: 'Execuções',
                executed: financialSummary.totalCompleted,
                pending: financialSummary.totalPlanned,
                noShow: financialSummary.totalFailed,
                gap: financialSummary.totalCompletedWithGaps,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: VeraProbColors.border, height: 1),
          const SizedBox(height: 20),
          ContractAmendmentsTimeline(contractId: contractId),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final int value;
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
    return SizedBox(
      width: 220, // Base width for wrap items
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
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: VeraProbColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _currencyFormat.format(value / 100.0),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
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
    return SizedBox(
      width: 220, // Base width for wrap items
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: VeraProbColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _countRow('Executados', executed, VeraProbColors.onTime),
              _countRow('Pendentes', pending, VeraProbColors.scheduled),
              _countRow('No-show', noShow, VeraProbColors.error),
              _countRow('Gap evidência', gap, VeraProbColors.warning),
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(lbl, style: const TextStyle(fontSize: 11)),
          const Spacer(),
          Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Forensic Seal widget (INV-34) ─────────────────────────────────────────────

class _ForensicSealSection extends StatelessWidget {
  final String? previousHash;
  final String? currentHash;

  const _ForensicSealSection({
    required this.previousHash,
    required this.currentHash,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 13,
                color: VeraProbColors.textSecondary,
              ),
              SizedBox(width: 6),
              Text(
                'Selo Forense (INV-34)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: VeraProbColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (previousHash != null)
            _HashRow(label: 'Hash anterior', hash: previousHash!),
          if (previousHash != null && currentHash != null)
            const SizedBox(height: 4),
          if (currentHash != null)
            _HashRow(label: 'Hash atual', hash: currentHash!),
        ],
      ),
    );
  }
}

class _HashRow extends StatelessWidget {
  final String label;
  final String hash;

  const _HashRow({required this.label, required this.hash});

  String get _truncated =>
      hash.length > 20 ? '${hash.substring(0, 20)}…' : hash;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: VeraProbColors.textDisabled,
            ),
          ),
        ),
        Expanded(
          child: Text(
            _truncated,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: VeraProbColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            Clipboard.setData(ClipboardData(text: hash));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label copiado'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(
              Icons.copy_outlined,
              size: 13,
              color: VeraProbColors.textDisabled,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final ContractStatusView status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return VeraProbChip(
      label: switch (status) {
        ContractStatusView.draft => 'Rascunho',
        ContractStatusView.awaitingContractorAcceptance => 'Aguardando Aceite',
        ContractStatusView.active => 'Ativo',
        ContractStatusView.closed => 'Encerrado',
      },
      color: switch (status) {
        ContractStatusView.draft => VeraProbColors.neutral,
        ContractStatusView.awaitingContractorAcceptance => VeraProbColors.info,
        ContractStatusView.active => VeraProbColors.success,
        ContractStatusView.closed => VeraProbColors.error,
      },
    );
  }
}

class _ExecutionStatusChip extends StatelessWidget {
  final ExecutionStatus status;

  const _ExecutionStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ExecutionStatus.planned => ('Planejada', VeraProbColors.info),
      ExecutionStatus.inTransit => ('Em Trânsito', VeraProbColors.primary),
      ExecutionStatus.completed => ('Concluída', VeraProbColors.success),
      ExecutionStatus.completedWithGaps => (
        'C/ Pendências',
        VeraProbColors.warning,
      ),
      ExecutionStatus.failed => ('Falha', VeraProbColors.error),
      ExecutionStatus.inhibited => ('Inibida', VeraProbColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
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
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: VeraProbColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ],
    );
  }
}
