import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Administração — the launcher that consolidates every registry, rule and
/// governance screen behind a single sidebar pillar. Cards drive
/// [adminIndexProvider] to the target [AdminNav] screen; the shell renders a
/// "Voltar para Administração" bar while a deep screen is open.
///
/// WS-4: the Evidências card is visible only to AUDITOR and TENANT_ADMIN.
class AdminHubScreen extends ConsumerWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider);
    final canSeeEvidence = role.hasPermission(UserRole.auditor);

    final groups = <_HubGroup>[
      const _HubGroup(
        title: 'Cadastros & Recursos',
        items: [
          _HubItem(
            label: 'Motoristas',
            icon: Icons.people_outlined,
            destination: AdminNav.drivers,
          ),
          _HubItem(
            label: 'Zonas Operacionais',
            icon: Icons.place_outlined,
            destination: AdminNav.zones,
          ),
          _HubItem(
            label: 'Contratantes',
            icon: Icons.handshake_outlined,
            destination: AdminNav.contractors,
          ),
        ],
      ),
      const _HubGroup(
        title: 'Regras & Contratos',
        items: [
          _HubItem(
            label: 'Contratos',
            icon: Icons.description_outlined,
            destination: AdminNav.contracts,
          ),
          _HubItem(
            label: 'Modelos SLA',
            icon: Icons.library_books_outlined,
            destination: AdminNav.slaTemplates,
          ),
          _HubItem(
            label: 'Auditoria de SLA',
            icon: Icons.verified_user_outlined,
            destination: AdminNav.slaAudit,
          ),
        ],
      ),
      const _HubGroup(
        title: 'Operação & Relatórios',
        items: [
          _HubItem(
            label: 'Ponto Eletrônico',
            icon: Icons.access_time_outlined,
            destination: AdminNav.timecards,
          ),
          _HubItem(
            label: 'Relatórios',
            icon: Icons.summarize_outlined,
            destination: AdminNav.billingReports,
          ),
        ],
      ),
      _HubGroup(
        title: 'Conta & Governança',
        items: [
          const _HubItem(
            label: 'Organização',
            icon: Icons.business_outlined,
            destination: AdminNav.orgSettings,
          ),
          const _HubItem(
            label: 'Usuários',
            icon: Icons.manage_accounts_outlined,
            destination: AdminNav.userManagement,
          ),
          const _HubItem(
            label: 'Ajustes',
            icon: Icons.settings_outlined,
            destination: AdminNav.settings,
          ),
          if (canSeeEvidence)
            const _HubItem(
              label: 'Evidências',
              icon: Icons.folder_special_outlined,
              destination: AdminNav.evidence,
            ),
        ],
      ),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      children: [
        Text('Administração', style: VeraProbTypography.kpiValue),
        const SizedBox(height: 4),
        Text(
          'Cadastros, regras e governança operacional',
          style: VeraProbTypography.bodySmall.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
        const SizedBox(height: 32),
        for (final group in groups) ...[
          _GroupHeader(title: group.title),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / 280).floor().clamp(1, 4);
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2.6,
                children: [
                  for (final item in group.items)
                    _HubCard(
                      item: item,
                      onTap: () => ref
                          .read(adminIndexProvider.notifier)
                          .go(item.destination),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: VeraProbTypography.kpiLabel.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: VeraProbColors.border)),
      ],
    );
  }
}

class _HubCard extends StatefulWidget {
  final _HubItem item;
  final VoidCallback onTap;
  const _HubCard({required this.item, required this.onTap});

  @override
  State<_HubCard> createState() => _HubCardState();
}

class _HubCardState extends State<_HubCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.item.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hovered ? 1.0 : 0.98,
            duration: const Duration(milliseconds: 150),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: VeraProbColors.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _hovered
                          ? VeraProbColors.primary.withValues(alpha: 0.4)
                          : const Color(0x0FFFFFFF),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.item.icon,
                        size: 22,
                        color: _hovered
                            ? VeraProbColors.primary
                            : VeraProbColors.textSecondary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          widget.item.label,
                          style: VeraProbTypography.dataValue,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: VeraProbColors.textDisabled,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HubGroup {
  final String title;
  final List<_HubItem> items;
  const _HubGroup({required this.title, required this.items});
}

class _HubItem {
  final String label;
  final IconData icon;
  final AdminNav destination;
  const _HubItem({
    required this.label,
    required this.icon,
    required this.destination,
  });
}
