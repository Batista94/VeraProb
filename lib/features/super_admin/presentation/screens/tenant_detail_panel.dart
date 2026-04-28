import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_health_card.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_secret_card.dart';

/// Right panel: detail view for a selected tenant organization.
///
/// Stage H: Split-view layout — this panel fills the remaining space.
/// Tabs: Overview (Health Cards), Configuração, Audit Log.
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
              _StatusBadge(isActive: t.isActive),
              const SizedBox(width: 8),
              _PlanBadge(planType: t.planType),
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

/// Metrics tab: Health cards in a 2x2 grid.
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

/// Configuration tab: plan, capabilities, operational params.
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

/// Security tab: HMAC secret management.
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

// ── Shared helper widgets ────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? VeraProbColors.success : VeraProbColors.error)
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Ativo' : 'Inativo',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isActive ? VeraProbColors.success : VeraProbColors.error,
        ),
      ),
    );
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
