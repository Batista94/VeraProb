import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/screens/access_management_tab.dart';
import 'package:veraprob/features/admin/presentation/screens/org_settings_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/user_management_screen.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/admin/access_management_service.dart';
import 'package:veraprob/state/providers/access_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Hub consolidado para as configurações do sistema, organização e gestão de usuários.
/// Roteado via `/admin/hub/settings`.
/// Suporta deep link por query parameter `?tab=` (`org`, `users` ou `access`).
class SettingsHubScreen extends ConsumerWidget {
  final String? initialTab;

  const SettingsHubScreen({super.key, this.initialTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget(
      asyncValue: ref.watch(authStateProvider),
      showRefreshIndicator: false,
      data: (_) => _SettingsHubBody(initialTab: initialTab),
    );
  }
}

class _SettingsHubBody extends ConsumerStatefulWidget {
  final String? initialTab;

  const _SettingsHubBody({this.initialTab});

  @override
  ConsumerState<_SettingsHubBody> createState() => _SettingsHubBodyState();
}

class _SettingsHubBodyState extends ConsumerState<_SettingsHubBody>
        // TickerProviderStateMixin (not Single*): a live roles:manage flip recreates
        // the TabController, so more than one ticker exists over this State's life.
        with
        TickerProviderStateMixin {
  late TabController _tabController;

  late bool _canManageOrg;
  late bool _canViewAccess;

  @override
  void initState() {
    super.initState();
    _syncPermissions();
    final initialIndex = _getInitialIndex(widget.initialTab);
    _tabController = TabController(
      length: _getTabCount(),
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  void _syncPermissions() {
    final perms = ref.read(permissionServiceProvider);
    _canManageOrg =
        perms.hasPermission('org:manage') ||
        perms.hasPermission('roles:manage');
    _canViewAccess =
        perms.hasPermission('roles:read') ||
        perms.hasPermission('roles:manage');
  }

  int _getTabCount() {
    int count = 2; // Geral and Equipe are always visible
    if (_canManageOrg) count++;
    if (_canViewAccess) count++;
    return count;
  }

  int _getInitialIndex(String? tab) {
    if (tab == 'org' && _canManageOrg) return 1;
    if (tab == 'users') return _canManageOrg ? 2 : 1;
    if (tab == 'access' && _canViewAccess) return _canManageOrg ? 3 : 2;
    return 0; // default to general settings
  }

  @override
  void didUpdateWidget(_SettingsHubBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _tabController.animateTo(_getInitialIndex(widget.initialTab));
    }
  }

  /// Re-shapes the tab set when live permissions flip.
  void _syncTabs() {
    final oldController = _tabController;
    final newLength = _getTabCount();
    final newController = TabController(
      length: newLength,
      vsync: this,
      initialIndex: oldController.index.clamp(0, newLength - 1),
    );
    setState(() {
      _tabController = newController;
    });
    oldController.dispose();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Live permission parity
    ref.listen(permissionServiceProvider, (previous, next) {
      final newCanManageOrg =
          next.hasPermission('org:manage') ||
          next.hasPermission('roles:manage');
      final newCanViewAccess =
          next.hasPermission('roles:read') ||
          next.hasPermission('roles:manage');

      if (newCanManageOrg != _canManageOrg ||
          newCanViewAccess != _canViewAccess) {
        _canManageOrg = newCanManageOrg;
        _canViewAccess = newCanViewAccess;
        _syncTabs();
      }
    });

    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              VeraProbSpacing.lg,
              VeraProbSpacing.md,
              VeraProbSpacing.lg,
              0,
            ),
            child: VeraProbHeader(
              icon: Icons.settings_outlined,
              title: 'Configurações',
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: VeraProbColors.primary,
            unselectedLabelColor: VeraProbColors.textSecondary,
            indicatorColor: VeraProbColors.primary,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Geral'),
              if (_canManageOrg) const Tab(text: 'Organização'),
              const Tab(text: 'Equipe'),
              if (_canViewAccess) const Tab(text: 'Acessos'),
            ],
          ),
          const Divider(height: 1, color: VeraProbColors.border),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const _GeneralSettingsTab(),
                if (_canManageOrg) const OrgSettingsTab(),
                const UserManagementTab(),
                if (_canViewAccess) const AccessManagementTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A aba "Geral" contendo informações de conectividade e sessão da tela antiga.
class _GeneralSettingsTab extends ConsumerWidget {
  const _GeneralSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider).value;
    final user = authState?.session?.user;
    final rawName = user?.userMetadata?['name'] as String?;
    final rawEmail = user?.email ?? '';
    final role = ref.watch(currentUserRoleProvider);
    final userId = ref.watch(currentOperatorIdProvider);
    final roles = ref.watch(tenantRolesProvider).value ?? const <TenantRole>[];
    final assignments =
        ref.watch(activeRoleAssignmentsProvider).value ??
        const <RoleAssignment>[];

    String operatorName = 'Usuário';
    if (rawName != null && rawName.trim().isNotEmpty) {
      operatorName = rawName.trim();
    } else if (rawEmail.isNotEmpty) {
      operatorName = rawEmail;
    }

    // The parenthetical reflects the person's real profile in the tool: their
    // highest-privilege tenant role (which alone knows "Validador"), falling
    // back to the coarse trust-root label when no tenant role is assigned.
    final coarseLabel = switch (role) {
      UserRole.admin => 'Administrador',
      UserRole.operator => 'Operador',
      UserRole.auditor => 'Auditor',
      UserRole.contractorViewer => 'Visualizador',
      UserRole.superAdmin => 'Super Administrador',
    };
    final profileLabel = userId == null
        ? coarseLabel
        : highestPrivilegeRoleName(
                userId: userId,
                assignments: assignments,
                roles: roles,
              ) ??
              coarseLabel;

    final displayIdentity = '$operatorName ($profileLabel)';
    final operatorId = user?.id ?? 'Não autenticado';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(VeraProbSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CONFIGURAÇÕES DO SISTEMA',
              style: VeraProbTypography.sectionTitle.copyWith(
                color: VeraProbColors.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            Text(
              'Gerencie as preferências globais do Centro de Controle.',
              style: VeraProbTypography.bodySmall,
            ),
            const SizedBox(height: VeraProbSpacing.xl),

            // ── Seção: Sessão Atual ────────────────
            const _SectionHeader(title: 'Sessão Atual'),
            _SettingTile(
              label: 'Operador Conectado',
              value: displayIdentity,
              icon: Icons.person_outline,
            ),
            _SettingTile(
              label: 'ID do Operador',
              value: operatorId,
              icon: Icons.badge_outlined,
            ),

            const SizedBox(height: VeraProbSpacing.xl),

            // ── Seção: Conectividade ───────────────
            const _SectionHeader(title: 'Dados e Conectividade'),
            const _SettingTile(
              label: 'Telemetria',
              value: 'Real-time (Supabase)',
              icon: Icons.sensors,
            ),

            const SizedBox(height: VeraProbSpacing.xl),

            // ── Seção: Informações Técnicas ───────
            const _SectionHeader(title: 'Sobre a Plataforma'),
            const _SettingTile(
              label: 'Versão do Software',
              value: '1.0.0-b2b.hardening',
              icon: Icons.info_outline,
            ),
            const _SettingTile(
              label: 'Ambiente',
              value: 'Desenvolvimento / Simulação',
              icon: Icons.code,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: VeraProbTypography.caption.copyWith(
            color: VeraProbColors.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Divider(height: 24, color: VeraProbColors.border),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SettingTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: VeraProbColors.textSecondary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: VeraProbTypography.caption),
              Text(
                value,
                style: VeraProbTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
