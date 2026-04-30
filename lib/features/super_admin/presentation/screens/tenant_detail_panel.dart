import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/archive_confirmation_dialog.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/reason_confirmation_dialog.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_config_tab.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_metrics_tab.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_panel_badges.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_security_tab.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_audit_tab.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_users_tab.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Right panel: detail view for a selected tenant organization.
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
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void didUpdateWidget(covariant TenantDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // INV-11: Reseta o tab ao trocar de tenant para evitar contexto stale.
    if (oldWidget.tenant.id != widget.tenant.id) {
      _tabController.index = 0;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _archiveOrg(TenantHealthView t) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ArchiveConfirmationDialog(),
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
      ref.invalidate(tenantDetailProvider(t.id));
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

  Future<void> _unarchiveOrg(TenantHealthView t) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ReasonConfirmationDialog(),
    );
    if (reason == null || !mounted) return;

    try {
      final repo = ref.read(superAdminRepositoryProvider);
      final userId =
          ref.read(authStateProvider).valueOrNull?.session?.user.id ?? '';
      await repo.unarchiveOrganization(
        orgId: t.id,
        reason: reason,
        superAdminId: userId,
      );
      ref.invalidate(tenantHealthSnapshotProvider);
      ref.invalidate(tenantDetailProvider(t.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Organização desarquivada com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao desarquivar: $e'),
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
              OrgStatusBadge(label: t.status?.label),
              const SizedBox(width: 8),
              PlanBadge(planType: t.planType),
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
              if (t.isArchived) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _unarchiveOrg(t),
                  icon: const Icon(Icons.unarchive_outlined, size: 16),
                  label: const Text('Desarquivar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: VeraProbColors.success,
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
            Tab(text: 'Usuários'),
            Tab(text: 'Auditoria'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              TenantMetricsTab(tenant: t),
              TenantConfigTab(tenant: t),
              TenantSecurityTab(tenant: t),
              TenantUsersTab(tenant: t),
              TenantAuditTab(organizationId: t.id),
            ],
          ),
        ),
      ],
    );
  }
}
