import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_health_card.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_secret_card.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Right panel: detail view for a selected tenant organization.
///
/// Stage H: Split-view layout — this panel fills the remaining space.
/// Tabs: Métricas (Health Cards), Configuração, Segurança.
class TenantDetailPanel extends ConsumerStatefulWidget {
  final TenantHealthView tenant;

  const TenantDetailPanel({super.key, required this.tenant});

  @override
  ConsumerState<TenantDetailPanel> createState() => _TenantDetailPanelState();
}

class _TenantDetailPanelState extends ConsumerState<TenantDetailPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _archiveOrg(TenantHealthView t) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ArchiveConfirmationDialog(),
    );
    if (reason == null || !mounted) return;

    try {
      final handler = ref.read(archiveOrganizationHandlerProvider);
      final userId =
          ref.read(authStateProvider).valueOrNull?.session?.user.id ?? '';
      final sessionId = ref.read(currentSessionIdProvider) ?? '';
      await handler.handlePrimitives(
        orgId: t.id,
        reason: reason,
        superAdminUserId: userId,
        currentStatusKey: t.statusKey,
        sessionId: sessionId,
      );

      ref.invalidate(tenantHealthSnapshotProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organização arquivada com sucesso.')),
        );
      }
    } on DomainException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao arquivar: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tenant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (t.legalName != null)
                      Text(
                        t.legalName!,
                        style: const TextStyle(
                          color: VeraProbColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              _OrgStatusBadge(label: t.status?.label),
              const SizedBox(width: 8),
              _PlanBadge(planType: t.planType),
              if (t.isOperational) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _archiveOrg(t),
                  icon: const Icon(Icons.archive_outlined, size: 16),
                  label: const Text('Arquivar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: VeraProbColors.warning,
                    side: const BorderSide(color: VeraProbColors.warning),
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            t.id,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: VeraProbColors.textDisabled,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Tabs ───────────────────────────────────────────────────
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: VeraProbColors.secondary,
          unselectedLabelColor: VeraProbColors.textSecondary,
          indicatorColor: VeraProbColors.secondary,
          tabs: const [
            Tab(text: 'Métricas'),
            Tab(text: 'Configuração'),
            Tab(text: 'Segurança'),
          ],
        ),
        const Divider(height: 1),

        // ── Tab content ────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _MetricsTab(tenant: t),
              _ConfigTab(tenant: t),
              _SecurityTab(tenant: t),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Tabs ─────────────────────────────────────────────────────────────────────

class _MetricsTab extends StatelessWidget {
  final TenantHealthView tenant;
  const _MetricsTab({required this.tenant});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          SizedBox(
            width: 240,
            child: OrgHealthCard(
              title: 'Contratos Ativos',
              value: '${tenant.activeContractCount}',
              icon: Icons.description_outlined,
              valueColor: tenant.activeContractCount > 0
                  ? VeraProbColors.success
                  : VeraProbColors.textSecondary,
            ),
          ),
          SizedBox(
            width: 240,
            child: OrgHealthCard(
              title: 'Limite de Veículos',
              value: tenant.maxVehicles == 0
                  ? 'Ilimitado'
                  : '${tenant.maxVehicles}',
              icon: Icons.local_shipping_outlined,
            ),
          ),
          SizedBox(
            width: 240,
            child: OrgHealthCard(
              title: 'Última Telemetria',
              value: tenant.lastTelemetryAt != null
                  ? _formatDateTime(tenant.lastTelemetryAt!)
                  : 'Nunca',
              icon: Icons.satellite_alt_outlined,
              valueColor: tenant.lastTelemetryAt == null
                  ? VeraProbColors.textDisabled
                  : null,
            ),
          ),
          SizedBox(
            width: 240,
            child: OrgHealthCard(
              title: 'Alertas Críticos',
              value: '${tenant.openCriticalAlertCount}',
              icon: Icons.warning_amber_outlined,
              valueColor: tenant.hasCriticalAlerts
                  ? VeraProbColors.error
                  : VeraProbColors.success,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ConfigTab extends StatelessWidget {
  final TenantHealthView tenant;
  const _ConfigTab({required this.tenant});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Plano & Limites'),
          const SizedBox(height: 8),
          _DetailRow('Plano', tenant.planType?.toUpperCase() ?? '—'),
          _DetailRow(
            'Max Veículos',
            tenant.maxVehicles == 0 ? 'Ilimitado' : '${tenant.maxVehicles}',
          ),
          _DetailRow(
            'Max Contratos',
            tenant.maxActiveContracts == 0
                ? 'Ilimitado'
                : '${tenant.maxActiveContracts}',
          ),
          _DetailRow(
            'Custo Ferramenta',
            tenant.toolCostCents != null
                ? 'R\$ ${(tenant.toolCostCents! / 100).toStringAsFixed(2)}'
                : '—',
          ),
          _DetailRow('Dwell Time', '${tenant.dwellTimeSeconds}s'),
          const SizedBox(height: 24),
          const _SectionTitle('Faturamento & Integração'),
          const SizedBox(height: 8),
          _DetailRow(
            'Dia de Faturamento',
            tenant.billingDay != null ? 'Dia ${tenant.billingDay}' : '—',
          ),
          _DetailRow('E-mail de Contato', tenant.contactEmail ?? '—'),
          _DetailRow('ID Externo', tenant.externalId ?? '—'),
          const SizedBox(height: 24),
          const _SectionTitle('Capabilities'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _CapChip('Lacre', tenant.capabilities.allowsSealing),
              _CapChip('Carregamento', tenant.capabilities.allowsLoading),
              _CapChip('Cargo Check', tenant.capabilities.allowsCargoCheck),
              _CapChip('Incidente', tenant.capabilities.allowsIncident),
              _CapChip('Doc', tenant.capabilities.allowsDoc),
              _CapChip('Smart Classify', tenant.capabilities.smartClassify),
              if (tenant.capabilities.maxKinematicSpeedKmh != null)
                _CapChip(
                  'Speed: ${tenant.capabilities.maxKinematicSpeedKmh} km/h',
                  true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecurityTab extends StatelessWidget {
  final TenantHealthView tenant;
  const _SecurityTab({required this.tenant});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrgSecretCard(
            organizationId: tenant.id,
            organizationName: tenant.name,
          ),
        ],
      ),
    );
  }
}

// ── Dialogs ───────────────────────────────────────────────────────────────────

class _ArchiveConfirmationDialog extends StatefulWidget {
  const _ArchiveConfirmationDialog();

  @override
  State<_ArchiveConfirmationDialog> createState() =>
      _ArchiveConfirmationDialogState();
}

class _ArchiveConfirmationDialogState
    extends State<_ArchiveConfirmationDialog> {
  final _reasonCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.archive_outlined, color: VeraProbColors.warning, size: 20),
          SizedBox(width: 8),
          Text('Arquivar Organização'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta ação irá arquivar a organização. Todos os segredos de API '
                'serão revogados imediatamente. A organização não poderá mais '
                'receber telemetria ou gerar novos contratos.',
                style: TextStyle(
                  fontSize: 13,
                  color: VeraProbColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  hintText: 'Mínimo 10 caracteres',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'Motivo obrigatório.';
                  if (val.length < 10) return 'Mínimo 10 caracteres.';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: VeraProbColors.warning,
          ),
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(_reasonCtrl.text.trim());
            }
          },
          child: const Text('Confirmar Arquivamento'),
        ),
      ],
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────────

/// Multi-status badge replacing the old boolean _StatusBadge.
///
/// Uses [label] string from [OrgStatus.label] — no domain import needed.
class _OrgStatusBadge extends StatelessWidget {
  final String? label;
  const _OrgStatusBadge({this.label});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _resolve(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label ?? '—',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (Color, IconData?) _resolve(String? lbl) {
    switch (lbl) {
      case 'Ativo':
        return (VeraProbColors.success, null);
      case 'Trial':
        return (VeraProbColors.info, null);
      case 'Suspenso':
        return (VeraProbColors.delayed, Icons.pause_circle_outline);
      case 'Churned':
        return (VeraProbColors.warning, Icons.cancel_outlined);
      case 'Arquivado':
        return (Colors.amber, Icons.lock_outline);
      case 'Excluído':
        return (VeraProbColors.error, Icons.delete_outline);
      default:
        return (VeraProbColors.textSecondary, null);
    }
  }
}

class _PlanBadge extends StatelessWidget {
  final String? planType;
  const _PlanBadge({this.planType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: VeraProbColors.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        planType?.toUpperCase() ?? '—',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: VeraProbColors.secondary,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: VeraProbColors.textPrimary,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _CapChip extends StatelessWidget {
  final String label;
  final bool enabled;
  const _CapChip(this.label, this.enabled);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: enabled ? VeraProbColors.success : VeraProbColors.textDisabled,
        ),
      ),
      backgroundColor: enabled
          ? VeraProbColors.success.withValues(alpha: 0.1)
          : VeraProbColors.border.withValues(alpha: 0.3),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
