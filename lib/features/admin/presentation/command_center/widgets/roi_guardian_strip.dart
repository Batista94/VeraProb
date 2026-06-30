import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/forensic_ledger_providers.dart';

const Color _kLabelColor = Color(0xFF8899AA);
const Color _kLabelSubdued = Color(0xFF667788);
const Color _kDividerLine = Color(0xFF1A2A3A);

/// 42px ROI Guardian strip — Phase 10.
/// Shows recovered revenue, avoided penalties, auto-linked trips, and ROI %.
/// Streams from v_roi_summary via [roiSummaryProvider].
class RoiGuardianStrip extends ConsumerWidget {
  const RoiGuardianStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roiAsync = ref.watch(roiSummaryProvider);

    return Container(
      height: 42,
      color: VeraProbColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: switch (roiAsync) {
        AsyncLoading() => const Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: VeraProbColors.primary,
            ),
          ),
        ),
        AsyncError() => const SizedBox.shrink(),
        AsyncData(:final value) => _buildRoiContent(value),
      },
    );
  }

  Widget _buildRoiContent(RoiSummary? value) {
    if (value == null) return const SizedBox.shrink();
    // Horizontal scroll: prevents overflow on narrow windows (Lesson #3)
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 14,
            color: VeraProbColors.primary,
          ),
          const SizedBox(width: 6),
          _Metric(
            label: 'RECEITA RECUPERADA',
            value: _formatCents(value.totalRecoveredCents),
            color: VeraProbColors.success,
          ),
          _Divider(),
          _Metric(
            label: 'GLOSAS EVITADAS',
            value: _formatCents(value.totalAvoidedPenaltyCents),
            color: VeraProbColors.warning,
          ),
          _Divider(),
          _RoiAtualMetric(roiBps: value.roiBps),
          _Divider(),
          _Metric(
            label: 'VIAGENS AUTO-VINCULADAS',
            value: value.totalLinkedTrips.toString(),
            color: VeraProbColors.primary,
          ),
          if (value.pendingOrphans > 0) ...[
            _Divider(),
            _Metric(
              label: 'ÓRFÃOS PENDENTES',
              value: value.pendingOrphans.toString(),
              color: VeraProbColors.error,
            ),
          ],
        ],
      ),
    );
  }

  String _formatCents(int cents) {
    final formatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return formatter.format(cents / 100);
  }
}

/// ROI ATUAL metric with visually distinct N/A state + actionable hint.
class _RoiAtualMetric extends StatelessWidget {
  final int? roiBps;
  const _RoiAtualMetric({required this.roiBps});

  @override
  Widget build(BuildContext context) {
    if (roiBps == null) {
      // N/A: visually distinct — dashed border + actionable subtitle
      return Tooltip(
        message: 'Defina tool_cost_cents na organização para calcular o ROI',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: _kLabelColor.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ROI ATUAL: N/A',
                style: TextStyle(
                  fontSize: 9,
                  color: _kLabelColor,
                  fontFamily: 'Outfit',
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                'Configure o custo do contrato',
                style: TextStyle(
                  fontSize: 7,
                  color: _kLabelSubdued,
                  fontFamily: 'Outfit',
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final percent = (roiBps! / 100).toStringAsFixed(1);
    final color = roiBps! >= 0 ? VeraProbColors.success : VeraProbColors.error;

    return _Metric(label: 'ROI ATUAL', value: '$percent%', color: color);
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
            color: _kLabelColor,
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
        child: VerticalDivider(width: 1, color: _kDividerLine),
      ),
    );
  }
}
