import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/forensic_ledger_providers.dart';

/// 42px ROI Guardian strip — Phase 10.
/// Shows recovered revenue, avoided penalties, and auto-linked trips.
/// Streams from v_roi_summary via [roiSummaryProvider].
class RoiGuardianStrip extends ConsumerWidget {
  const RoiGuardianStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roiAsync = ref.watch(roiSummaryProvider);

    return Container(
      height: 42,
      color: const Color(0xFF0A1628), // dark navy — SOC palette
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: roiAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: VeraProbColors.primary,
            ),
          ),
        ),
        error: (_, _) => const SizedBox.shrink(),
        data: (roi) {
          if (roi == null) return const SizedBox.shrink();
          return Row(
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 14,
                color: VeraProbColors.primary,
              ),
              const SizedBox(width: 6),
              _Metric(
                label: 'RECEITA RECUPERADA',
                value: _formatCents(roi.totalRecoveredCents),
                color: VeraProbColors.success,
              ),
              _Divider(),
              _Metric(
                label: 'GLOSAS EVITADAS',
                value: _formatCents(roi.totalAvoidedPenaltyCents),
                color: VeraProbColors.warning,
              ),
              _Divider(),
              _Metric(
                label: 'VIAGENS AUTO-VINCULADAS',
                value: roi.totalLinkedTrips.toString(),
                color: VeraProbColors.primary,
              ),
              if (roi.pendingOrphans > 0) ...[
                _Divider(),
                _Metric(
                  label: 'ÓRFÃOS PENDENTES',
                  value: roi.pendingOrphans.toString(),
                  color: VeraProbColors.error,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _formatCents(int cents) {
    final formatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return formatter.format(cents / 100);
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 9,
            color: Color(0xFF8899AA),
            fontFamily: 'Outfit',
            letterSpacing: 0.8,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            fontFamily: 'Outfit',
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 20,
        child: VerticalDivider(width: 1, color: Color(0xFF1A2A3A)),
      ),
    );
  }
}
