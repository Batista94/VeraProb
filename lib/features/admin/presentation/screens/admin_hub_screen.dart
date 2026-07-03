import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/admin/providers/onboarding_provider.dart';

/// Administração — the launcher that consolidates every registry, rule and
/// governance screen behind a single sidebar pillar. Cards navigate to the
/// target [AdminNav] screen via `context.go(item.destination.path)`; the shell
/// renders a "Voltar para Administração" bar while a deep screen is open.
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
          _HubItem(
            label: 'Risco da Frota',
            icon: Icons.insights_outlined,
            routePath: AppRoutes.fleetRiskAnalytics,
          ),
        ],
      ),
      _HubGroup(
        title: 'Conta & Governança',
        items: [
          const _HubItem(
            label: 'Configurações',
            icon: Icons.settings_outlined,
            destination: AdminNav.settings,
          ),
          if (role.hasPermission(UserRole.admin))
            const _HubItem(
              label: 'Integrações (Webhooks)',
              icon: Icons.webhook_outlined,
              destination: AdminNav.webhooks,
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
        const SizedBox(height: 12),
        const _HubOnboardingBanner(),
        const SizedBox(height: 20),
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
                    _HubCard(item: item, onTap: () => context.go(item.path)),
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
              borderRadius: VeraProbRadii.lgAll,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: VeraProbColors.surface.withValues(alpha: 0.7),
                    borderRadius: VeraProbRadii.lgAll,
                    border: Border.all(
                      color: _hovered
                          ? VeraProbColors.primary.withValues(alpha: 0.4)
                          : VeraProbColors.border.withValues(alpha: 0.1),
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

  /// Target sidebar destination, when the card maps to an [AdminNav] branch.
  final AdminNav? destination;

  /// Explicit route path, for cards that target a nested route with no
  /// [AdminNav] of its own (e.g. the Fleet Risk analytics dashboard).
  final String? routePath;

  const _HubItem({
    required this.label,
    required this.icon,
    this.destination,
    this.routePath,
  }) : assert(
         destination != null || routePath != null,
         'A hub item needs either a destination or a routePath.',
       );

  /// Resolved navigation target.
  String get path => routePath ?? destination!.path;
}

class _HubOnboardingBanner extends ConsumerWidget {
  const _HubOnboardingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(onboardingProgressProvider);
    if (progress.isComplete) return const SizedBox.shrink();

    final nextStep = progress.steps.firstWhere((s) => !s.isFulfilled);
    final stepIndex = progress.completedCount + 1;

    return ClipRRect(
      borderRadius: VeraProbRadii.lgAll,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: VeraProbColors.surface.withValues(alpha: 0.5),
            borderRadius: VeraProbRadii.lgAll,
            border: Border.all(
              color: VeraProbColors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: VeraProbColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  size: 18,
                  color: VeraProbColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Passo $stepIndex de 5: Configurar ${nextStep.label}',
                      style: VeraProbTypography.dataValue.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nextStep.description,
                      style: VeraProbTypography.bodySmall.copyWith(
                        color: VeraProbColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                label: Text(
                  'CONFIGURAR AGORA',
                  style: VeraProbTypography.badge.copyWith(
                    color: VeraProbColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  backgroundColor: VeraProbColors.primary.withValues(
                    alpha: 0.1,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: VeraProbRadii.mdAll,
                  ),
                ),
                onPressed: () => context.go(nextStep.destination.path),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
