import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';

/// Explicit indicator that the `disputed` lane is filtered to overdue items
/// only (via the SlaBreachBadge). Tapping clears the filter back to all
/// disputes.
class OverdueFilterBanner extends StatelessWidget {
  final int count;
  final VoidCallback onClear;

  const OverdueFilterBanner({
    super.key,
    required this.count,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    const red = VeraProbColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.alarm_outlined, size: 16, color: red),
          const SizedBox(width: 10),
          Text(
            'Filtrando $count disputa(s) com SLA vencido',
            style: const TextStyle(fontSize: 12, color: red),
          ),
          const Spacer(),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              foregroundColor: red,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: const Text('LIMPAR'),
          ),
        ],
      ),
    );
  }
}

class DateFilterBar extends ConsumerWidget {
  final TerminalLane lane;
  const DateFilterBar({super.key, required this.lane});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sealedSanctionsNotifierProvider(lane));
    String format(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.date_range_outlined,
            size: 16,
            color: VeraProbColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Text(
            'Período: ${format(state.startDate.toLocal())} até ${format(state.endDate.toLocal())}',
            style: VeraProbTypography.bodySmall,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: DateTimeRange(
                  start: state.startDate,
                  end: state.endDate,
                ),
                firstDate: DateTime(2025),
                lastDate: DateTime.now().toUtc().add(const Duration(days: 1)),
              );
              if (picked != null) {
                await ref
                    .read(sealedSanctionsNotifierProvider(lane).notifier)
                    .updateDateFilter(picked.start, picked.end);
              }
            },
            icon: const Icon(Icons.edit_calendar_outlined, size: 14),
            label: const Text('ALTERAR'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }
}
