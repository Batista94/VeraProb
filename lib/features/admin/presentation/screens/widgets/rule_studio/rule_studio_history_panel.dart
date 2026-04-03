import 'package:flutter/material.dart';

import 'package:veraprob/application/sla_audit/rule_version_history_entry.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';

import 'rule_studio_shared.dart';

/// Version history panel shown in the right column of the Rule Studio screen.
class RuleVersionHistoryPanel extends StatelessWidget {
  const RuleVersionHistoryPanel({super.key, required this.history});

  final List<RuleVersionHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_outlined,
              size: 48,
              color: VeraProbColors.textDisabled.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Nenhuma regra configurada ainda.',
              style: TextStyle(
                fontSize: 13,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // Group by rule type
    final grouped = <SlaRuleType, List<RuleVersionHistoryEntry>>{};
    for (final entry in history) {
      grouped.putIfAbsent(entry.ruleType, () => []).add(entry);
    }

    return ListView(
      children: grouped.entries.map((e) {
        return _HistoryGroup(ruleType: e.key, entries: e.value);
      }).toList(),
    );
  }
}

class _HistoryGroup extends StatefulWidget {
  const _HistoryGroup({required this.ruleType, required this.entries});

  final SlaRuleType ruleType;
  final List<RuleVersionHistoryEntry> entries;

  @override
  State<_HistoryGroup> createState() => _HistoryGroupState();
}

class _HistoryGroupState extends State<_HistoryGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  RuleTypeIcon(ruleType: widget.ruleType, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    ruleTypeLabel(widget.ruleType),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: VeraProbColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.entries.length} versões',
                    style: const TextStyle(
                      fontSize: 11,
                      color: VeraProbColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 14,
                    color: VeraProbColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ...widget.entries.map((entry) => _HistoryRow(entry: entry)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final RuleVersionHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: VeraProbColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.isActive
                  ? VeraProbColors.onTime
                  : VeraProbColors.textDisabled,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'v${entry.ruleVersion}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: VeraProbColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (entry.isActive)
                      const Text(
                        '(ativa)',
                        style: TextStyle(
                          fontSize: 10,
                          color: VeraProbColors.onTime,
                        ),
                      ),
                  ],
                ),
                Text(
                  _formatDateRange(entry),
                  style: const TextStyle(
                    fontSize: 10,
                    color: VeraProbColors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _configSummary(entry),
            style: const TextStyle(
              fontSize: 11,
              color: VeraProbColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateRange(RuleVersionHistoryEntry e) {
    final from = _fmtDate(e.activeFromUtc);
    if (e.isActive) return 'Desde $from';
    final to = _fmtDate(e.activeToUtc!);
    return '$from → $to';
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _configSummary(RuleVersionHistoryEntry e) {
    final c = e.config;
    return switch (e.ruleType.value) {
      'MAX_TOLERANCE_DELAY' => '${c['threshold_minutes']} min',
      'MAX_EVIDENCE_GAP' => '${c['max_gap_seconds']} s',
      'MIN_GEOFENCE_COVERAGE' => '${c['min_dwell_seconds']} s',
      'NO_SHOW_PENALTY' =>
        'R\$ ${(((c['penalty_amount_cents'] as int?) ?? 0) / 100).toStringAsFixed(2)}',
      _ => '',
    };
  }
}
