import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/features/admin/presentation/widgets/sla_breach_badge.dart';
import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/features/admin/presentation/screens/auditor_queue/widgets/auditor_empty_state.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';

class AuditorHeader extends ConsumerWidget {
  final AsyncValue<List<SanctionQueueItemView>> sanctionsAsync;
  final bool showMapToggle;
  final VoidCallback? onMapToggle;

  const AuditorHeader({
    super.key,
    required this.sanctionsAsync,
    this.showMapToggle = false,
    this.onMapToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(auditorQueueFilterProvider);
    final count = switch (sanctionsAsync) {
      AsyncData(:final value) => value.length,
      _ => 0,
    };
    final disputedCount = switch (ref.watch(disputedSanctionsStreamProvider)) {
      AsyncData(:final value) => value.length,
      _ => 0,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < VeraProbBreakpoints.compact;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            VeraProbHeader(
              icon: Icons.gavel_rounded,
              title: 'Tribunal de Auditoria',
              actions: [
                if (showMapToggle)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: 'Mapa Forense',
                      child: OutlinedButton.icon(
                        onPressed: onMapToggle,
                        icon: const Icon(Icons.map_outlined, size: 14),
                        label: isNarrow
                            ? const SizedBox.shrink()
                            : const Text('Mapa Forense'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: VeraProbColors.primary,
                          side: BorderSide(
                            color: VeraProbColors.primary.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          textStyle: const TextStyle(fontSize: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: const Size(36, 36),
                        ),
                      ),
                    ),
                  ),
                const SlaBreachBadge(),
                SimulateButton(isNarrow: isNarrow),
              ],
            ),
            const SizedBox(height: 16),
            AuditorTabs(
              selectedFilter: filter,
              pendingCount: count,
              disputedCount: disputedCount,
              isNarrow: isNarrow,
              onFilterChanged: (newFilter) {
                ref.read(disputeOverdueOnlyProvider.notifier).set(false);
                ref
                    .read(auditorQueueFilterProvider.notifier)
                    .setFilter(newFilter);
              },
            ),
          ],
        );
      },
    );
  }
}

class AuditorTabs extends StatelessWidget {
  final AuditorQueueFilter selectedFilter;
  final int pendingCount;
  final int disputedCount;
  final bool isNarrow;
  final ValueChanged<AuditorQueueFilter> onFilterChanged;

  const AuditorTabs({
    super.key,
    required this.selectedFilter,
    required this.pendingCount,
    required this.disputedCount,
    required this.isNarrow,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: VeraProbColors.surface.withValues(alpha: 0.3),
        borderRadius: VeraProbRadii.lgAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabItem(
              value: AuditorQueueFilter.pending,
              icon: Icons.pending_actions_outlined,
              label: 'Pendentes ($pendingCount)',
              isSelected: selectedFilter == AuditorQueueFilter.pending,
              onTap: () => onFilterChanged(AuditorQueueFilter.pending),
            ),
            const SizedBox(width: 4),
            TabItem(
              value: AuditorQueueFilter.disputed,
              icon: Icons.hourglass_empty_outlined,
              label: isNarrow
                  ? 'Disputa ($disputedCount)'
                  : 'Em Disputa ($disputedCount)',
              isSelected: selectedFilter == AuditorQueueFilter.disputed,
              onTap: () => onFilterChanged(AuditorQueueFilter.disputed),
            ),
            const SizedBox(width: 4),
            TabItem(
              value: AuditorQueueFilter.sealed,
              icon: Icons.verified_user_outlined,
              label: 'Concluídos',
              isSelected: selectedFilter == AuditorQueueFilter.sealed,
              onTap: () => onFilterChanged(AuditorQueueFilter.sealed),
            ),
            const SizedBox(width: 4),
            TabItem(
              value: AuditorQueueFilter.acknowledged,
              icon: Icons.handshake_outlined,
              label: 'De Acordo',
              isSelected: selectedFilter == AuditorQueueFilter.acknowledged,
              onTap: () => onFilterChanged(AuditorQueueFilter.acknowledged),
            ),
          ],
        ),
      ),
    );
  }
}

class TabItem extends StatefulWidget {
  final AuditorQueueFilter value;
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const TabItem({
    super.key,
    required this.value,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<TabItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const activeColor = VeraProbColors.primary;
    const inactiveColor = VeraProbColors.textSecondary;

    final textColor = widget.isSelected
        ? activeColor
        : (_isHovered ? VeraProbColors.textPrimary : inactiveColor);

    final iconColor = widget.isSelected
        ? activeColor
        : (_isHovered ? VeraProbColors.textPrimary : inactiveColor);

    final bgAlpha = widget.isSelected ? 0.15 : (_isHovered ? 0.05 : 0.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? activeColor.withValues(alpha: bgAlpha)
                : (_isHovered
                      ? VeraProbColors.textPrimary.withValues(alpha: bgAlpha)
                      : Colors.transparent),
            borderRadius: VeraProbRadii.mdAll,
            border: Border.all(
              color: widget.isSelected
                  ? activeColor.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: iconColor),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: widget.isSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  fontFamily: VeraProbTypography.base.fontFamily,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
