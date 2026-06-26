import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/keys/tenant_tab_keys.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/archive_confirmation_dialog.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/reason_confirmation_dialog.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_config_tab.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_health_tab.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_metrics_tab.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_panel_badges.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_security_tab.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_audit_tab.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_users_tab.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/impersonation_session_provider.dart';
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
    _tabController = TabController(length: 6, vsync: this);
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
    final messenger = ScaffoldMessenger.of(context);
    final reason = await ArchiveConfirmationDialog.show(context);
    if (reason == null || !mounted) return;

    try {
      final handler = ref.read(archiveOrganizationHandlerProvider);
      final userId = ref.read(authStateProvider).value?.session?.user.id ?? '';
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
        messenger.showSnackBar(
          const SnackBar(content: Text('Organização arquivada com sucesso.')),
        );
      }
    } on DomainException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Falha ao arquivar a organização.'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<void> _unarchiveOrg(TenantHealthView t) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ReasonConfirmationDialog(
        title: 'Desarquivar Organização',
        promptMessage:
            'Informe o motivo para o desarquivamento desta organização. '
            'Este registro será gravado no log de auditoria.',
      ),
    );
    if (reason == null || !mounted) return;

    try {
      final repo = ref.read(superAdminRepositoryProvider);
      final userId = ref.read(authStateProvider).value?.session?.user.id ?? '';
      await repo.unarchiveOrganization(
        orgId: t.id,
        reason: reason,
        superAdminId: userId,
      );
      ref.invalidate(tenantHealthSnapshotProvider);
      ref.invalidate(tenantDetailProvider(t.id));
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Organização desarquivada com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Falha ao desarquivar a organização.'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<void> _startImpersonation(TenantHealthView t) async {
    final ticketController = TextEditingController();
    final reasonController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Iniciar Personificação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ticketController,
              decoration: const InputDecoration(
                labelText: 'ID do Ticket (obrigatório)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Justificativa (mín. 10 caracteres)',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final handler = ref.read(startImpersonationHandlerProvider);
      final sessionId = ref.read(currentSessionIdProvider) ?? '';
      final session = await handler.handle(
        targetOrgId: t.id,
        ticketId: ticketController.text,
        reason: reasonController.text,
        callerRole: UserRole.superAdmin,
        sessionId: sessionId,
      );
      ref.read(activeImpersonationSessionProvider.notifier).set(session);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Personificando "${t.name}". Sessão expira em 30 minutos.',
            ),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } on DomainException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Falha ao iniciar personificação.'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      ticketController.dispose();
      reasonController.dispose();
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
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (t.legalName != null)
                      Text(
                        t.legalName!,
                        style: const TextStyle(
                          color: VeraProbColors.textSecondary,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              OrgStatusBadge(label: t.status?.label),
              PlanBadge(planType: t.planType),
              if (t.isOperational)
                Tooltip(
                  message: 'Arquivar',
                  child: OutlinedButton.icon(
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
                ),
              if (t.isOperational)
                Tooltip(
                  message: 'Iniciar Personificação',
                  child: OutlinedButton.icon(
                    onPressed: () => _startImpersonation(t),
                    icon: const Icon(Icons.person_search_outlined, size: 16),
                    label: const Text('Impersonar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: VeraProbColors.secondary,
                      side: const BorderSide(color: VeraProbColors.secondary),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              if (t.isArchived)
                Tooltip(
                  message: 'Desarquivar',
                  child: FilledButton.icon(
                    onPressed: () => _unarchiveOrg(t),
                    icon: const Icon(Icons.unarchive_outlined, size: 16),
                    label: const Text('Desarquivar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: VeraProbColors.success,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
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
          indicator: const _IndustrialTabIndicator(
            color: VeraProbColors.secondary,
          ),
          splashFactory: NoSplash.splashFactory,
          tabs: [
            for (final type in TenantTabKeys.allTabs)
              Semantics(
                identifier: TenantTabKeys.identifier(t.id, type),
                label: TenantTabKeys.label(type),
                child: Tab(
                  key: TenantTabKeys.tab(t.id, type),
                  text: _tabLabel(type),
                ),
              ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              TenantMetricsTab(
                key: TenantTabKeys.panel(t.id, TenantTabType.metrics),
                tenant: t,
              ),
              TenantHealthTab(
                key: TenantTabKeys.panel(t.id, TenantTabType.health),
                organizationId: t.id,
              ),
              TenantConfigTab(
                key: TenantTabKeys.panel(t.id, TenantTabType.config),
                tenant: t,
              ),
              TenantSecurityTab(
                key: TenantTabKeys.panel(t.id, TenantTabType.security),
                tenant: t,
              ),
              TenantUsersTab(
                key: TenantTabKeys.panel(t.id, TenantTabType.users),
                tenant: t,
              ),
              TenantAuditTab(
                key: TenantTabKeys.panel(t.id, TenantTabType.audit),
                organizationId: t.id,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _tabLabel(TenantTabType type) => switch (type) {
    TenantTabType.metrics => 'Métricas',
    TenantTabType.health => 'Saúde Técnica',
    TenantTabType.config => 'Configuração',
    TenantTabType.security => 'Segurança',
    TenantTabType.users => 'Usuários',
    TenantTabType.audit => 'Auditoria',
  };
}

/// Animated underline indicator with rounded caps — Industrial Deep style.
///
/// Uses implicit animation via [TabBar]'s built-in lerp between tab rects,
/// producing a smooth sliding effect (< 200ms per UX standards).
class _IndustrialTabIndicator extends Decoration {
  final Color color;

  const _IndustrialTabIndicator({required this.color});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _IndustrialPainter(color: color, onChanged: onChanged);
}

class _IndustrialPainter extends BoxPainter {
  final Color color;

  _IndustrialPainter({required this.color, VoidCallback? onChanged})
    : super(onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final width = configuration.size?.width ?? 0;
    final height = configuration.size?.height ?? 0;
    const indicatorHeight = 3.0;
    const radius = Radius.circular(1.5);

    final rect = RRect.fromLTRBAndCorners(
      offset.dx,
      offset.dy + height - indicatorHeight,
      offset.dx + width,
      offset.dy + height,
      topLeft: radius,
      topRight: radius,
    );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(rect, paint);
  }
}
