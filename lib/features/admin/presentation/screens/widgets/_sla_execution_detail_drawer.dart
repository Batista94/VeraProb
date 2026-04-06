import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/justification_providers.dart';
import 'package:veraprob/application/sla_audit/justification/generate_justification_token_command.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/investigation_modal.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

class SlaExecutionDetailDrawer extends ConsumerWidget {
  final SlaExecutionItemView item;

  const SlaExecutionDetailDrawer({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 400,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: VeraProbColors.surface,
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
                    Text(
                      'DADOS FINANCEIROS',
                      style: VeraProbTypography.caption,
                    ),
                    const SizedBox(height: 16),
                    _InfoField(
                      label: 'Valor Contratual',
                      value: _currencyFormat.format(
                        item.contractualValue.toDouble(),
                      ),
                    ),
                    _InfoField(
                      label: 'Multiplicador NoShow',
                      value:
                          '${(item.noShowPenaltyBps / 10000.0).toStringAsFixed(1)}x',
                    ),
                    if (item.status == ExecutionStatus.noShow)
                      _InfoField(
                        label: 'Penalidade Calculada',
                        value: _currencyFormat.format(
                          item.calculatedPenalty.toDouble(),
                        ),
                      ),
                    const Divider(height: 48),
                    Text(
                      'LOCAL DE ORIGEM (ZONA OPERACIONAL)',
                      style: VeraProbTypography.caption,
                    ),
                    const SizedBox(height: 16),
                    const _InfoField(
                      label: 'Referência Geográfica',
                      value: 'Ocultado (Confidencial B2B)',
                    ),
                    _InfoField(
                      label: 'Raio de Detecção',
                      value: '${item.startRadiusMeters} metros',
                    ),
                    if (item.status == ExecutionStatus.executed) ...[
                      const Divider(height: 48),
                      Text(
                        'EVIDÊNCIA DE EXECUÇÃO',
                        style: VeraProbTypography.caption,
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
            // ── Actions ───────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: VeraProbColors.border.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_canRequestDefense(item.status, role))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: _SolicitarDefesaButton(item: item),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          builder: (_) => InvestigationModal(
                            setId: item.setId,
                            contractId: item.contractId,
                          ),
                        );
                      },
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('Investigar Decisão'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VeraProbColors.secondary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
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

  String _formatFull(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  bool _canRequestDefense(ExecutionStatus status, UserRole role) {
    final isDefensibleStatus =
        status == ExecutionStatus.noShow ||
        status == ExecutionStatus.evidenceGap;
    final hasPermission = RbacService().can(
      role,
      UserPermission.canSubmitJustification,
    );
    return isDefensibleStatus && hasPermission;
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
            color: VeraProbColors.border.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Detalhes da Obrigação', style: VeraProbTypography.sectionTitle),
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
        color = VeraProbColors.error;
        label = 'NO SHOW';
        description =
            'Não detectado: Obrigação não executada na Zona Operacional.';
      case ExecutionStatus.evidenceGap:
        color = VeraProbColors.warning;
        label = 'EVIDENCE GAP';
        description =
            'Detecção Parcial: Indícios de Execução sem comprovação contínua.';
      case ExecutionStatus.executed:
        color = VeraProbColors.success;
        label = 'EXECUTADO';
        description = 'Evidência confirmada: Obrigação B2B cumprida.';
      case ExecutionStatus.pending:
        color = VeraProbColors.textSecondary;
        label = 'PENDENTE';
        description = 'Aguardando encerramento da janela.';
      case ExecutionStatus.inhibited:
        color = VeraProbColors.textSecondary;
        label = 'INIBIDO';
        description = 'Penalidade suprimida por justificativa aprovada.';
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
            style: VeraProbTypography.badge.copyWith(color: color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: VeraProbTypography.bodyMedium.copyWith(
            color: VeraProbColors.textSecondary,
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
            style: VeraProbTypography.caption.copyWith(
              color: VeraProbColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: VeraProbTypography.bodyMedium),
        ],
      ),
    );
  }
}

// ── Solicitar Defesa ──────────────────────────────────────────────────────────

/// Generates a single-use driver justification token and shows the copyable link.
///
/// Visible only for noShow/evidenceGap statuses for admin/operator (RBAC).
/// Token expiry defaults to 24 h (operator can select 1–72 h via a mini-dialog).
class _SolicitarDefesaButton extends ConsumerStatefulWidget {
  final SlaExecutionItemView item;
  const _SolicitarDefesaButton({required this.item});

  @override
  ConsumerState<_SolicitarDefesaButton> createState() =>
      _SolicitarDefesaButtonState();
}

class _SolicitarDefesaButtonState
    extends ConsumerState<_SolicitarDefesaButton> {
  bool _loading = false;

  Future<void> _generate() async {
    final orgId = ref.read(currentOrganizationIdProvider);
    final userId = ref.read(currentOperatorIdProvider);
    final role = ref.read(currentUserRoleProvider);
    if (orgId == null || userId == null) return;

    // Ask operator for expiry hours
    final hours = await _askExpiry(context);
    if (hours == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final token = await ref
          .read(generateJustificationTokenHandlerProvider)
          .handle(
            GenerateJustificationTokenCommand(
              organizationId: orgId,
              contractId: widget.item.contractId,
              setId: widget.item.setId,
              callerRole: role,
              callerUserId: userId,
              expiresInHours: hours,
            ),
          );

      if (!mounted) return;

      final uri = Uri.base.replace(
        path: '/justify',
        queryParameters: {'token': token.token},
      );
      final link = uri.toString();

      _showLinkDialog(context, link);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar link: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<int?> _askExpiry(BuildContext context) {
    int hours = 24;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Validade do Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Por quantas horas o link deve ser válido?',
                style: TextStyle(color: VeraProbColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Slider(
                value: hours.toDouble(),
                min: 1,
                max: 72,
                divisions: 71,
                label: '${hours}h',
                onChanged: (v) => setS(() => hours = v.round()),
              ),
              Text('$hours hora${hours > 1 ? 's' : ''}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, hours),
              child: const Text('Gerar Link'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLinkDialog(BuildContext context, String link) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Link de Defesa Gerado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compartilhe este link com o motorista. '
              'O link é de uso único e expira conforme configurado.',
              style: TextStyle(color: VeraProbColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VeraProbColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                link,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: VeraProbColors.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Link copiado!')));
            },
            child: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : () => _generate(),
      icon: _loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.link, size: 16),
      label: const Text('Solicitar Defesa'),
      style: OutlinedButton.styleFrom(
        foregroundColor: VeraProbColors.warning,
        side: const BorderSide(color: VeraProbColors.warning),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
