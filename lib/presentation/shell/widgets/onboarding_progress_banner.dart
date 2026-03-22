import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/enums/vehicle_status.dart';
import '../../../state/providers/operational_zone_providers.dart';
import '../../../state/providers/contractor_providers.dart';
import '../../../state/providers/sla_template_providers.dart';
import '../../../features/admin/providers/vehicles_provider.dart';

/// Slim top bar verifying 4 core master data prerequisites.
/// Renders as a 48px strip anchored above the main content — no layout displacement.
/// Auto-removes from DOM when all prerequisites are met.
class OnboardingProgressBanner extends ConsumerWidget {
  final ValueChanged<int> onNavigate;

  const OnboardingProgressBanner({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(operationalZonesProvider);
    final contractorsAsync = ref.watch(contractorListProvider);
    final vehiclesAsync = ref.watch(vehiclesListProvider);
    final rulesAsync = ref.watch(slaTemplatesProvider);

    final hasZones = (zonesAsync.valueOrNull ?? []).isNotEmpty;
    final hasContractors = (contractorsAsync.valueOrNull ?? []).isNotEmpty;
    final hasVehicles = (vehiclesAsync.valueOrNull ?? []).any(
      (v) =>
          v.status == VehicleStatus.available ||
          v.status == VehicleStatus.inService,
    );
    final hasRules = (rulesAsync.valueOrNull ?? []).isNotEmpty;

    final prerequisites = [
      _Prerequisite(label: 'Zonas', isFulfilled: hasZones, navIndex: 7),
      _Prerequisite(
        label: 'Contratantes',
        isFulfilled: hasContractors,
        navIndex: 11,
      ),
      _Prerequisite(label: 'Veículos', isFulfilled: hasVehicles, navIndex: 1),
      _Prerequisite(label: 'SLA Template', isFulfilled: hasRules, navIndex: 9),
    ];

    final completedCount = prerequisites.where((p) => p.isFulfilled).length;

    if (completedCount == prerequisites.length) {
      return const SizedBox.shrink(); // All green — remove from DOM
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _SlimBar(
        key: const ValueKey('onboarding_bar'),
        prerequisites: prerequisites,
        completedCount: completedCount,
        onNavigate: onNavigate,
      ),
    );
  }
}

class _Prerequisite {
  final String label;
  final bool isFulfilled;
  final int navIndex;

  const _Prerequisite({
    required this.label,
    required this.isFulfilled,
    required this.navIndex,
  });
}

class _SlimBar extends StatelessWidget {
  final List<_Prerequisite> prerequisites;
  final int completedCount;
  final ValueChanged<int> onNavigate;

  const _SlimBar({
    super.key,
    required this.prerequisites,
    required this.completedCount,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 1),
      decoration: const BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        border: Border(bottom: BorderSide(color: VeraProbColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            // Progress indicator
            SizedBox(
              width: 120,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuração  $completedCount/${prerequisites.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: VeraProbColors.textSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: completedCount / prerequisites.length,
                      backgroundColor: VeraProbColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        VeraProbColors.primary,
                      ),
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Prerequisite dots
            Expanded(
              child: Row(
                children: prerequisites
                    .map(
                      (p) => _PrerequisiteDot(
                        prerequisite: p,
                        onNavigate: onNavigate,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrerequisiteDot extends StatelessWidget {
  final _Prerequisite prerequisite;
  final ValueChanged<int> onNavigate;

  const _PrerequisiteDot({
    required this.prerequisite,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final color = prerequisite.isFulfilled
        ? VeraProbColors.success
        : VeraProbColors.error;

    return Tooltip(
      message: prerequisite.isFulfilled
          ? '${prerequisite.label}: configurado'
          : '${prerequisite.label}: pendente — clique para configurar',
      child: InkWell(
        // Fulfilled items are NOT interactive
        onTap: prerequisite.isFulfilled
            ? null
            : () => onNavigate(prerequisite.navIndex),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                prerequisite.isFulfilled
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                prerequisite.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: prerequisite.isFulfilled
                      ? VeraProbColors.textSecondary
                      : color,
                  decoration: prerequisite.isFulfilled
                      ? TextDecoration.none
                      : TextDecoration.underline,
                  decorationColor: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
